#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
current_system="$(nix eval --impure --raw --expr builtins.currentSystem)"

shopt -s nullglob

github_api() {
    local endpoint="$1"

    {
        if [[ -n ${GITHUB_TOKEN:-} ]]; then
            printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN"
        fi
    } | curl --config - -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/$endpoint"
}

update_package() {
    local package="$1"
    local config="$root/packages/$package/update.json"
    local sources="$root/packages/$package/sources.json"
    local repository tag_pattern asset_name release asset version url digest hash temporary

    if [[ ! -f $config ]]; then
        echo "No update configuration for package: $package" >&2
        return 1
    fi

    echo "Updating $package..."

    repository="$(jq --raw-output .repository "$config")"
    tag_pattern="$(jq --raw-output '.tagPattern // empty' "$config")"
    asset_name="$(jq --raw-output --arg system "$current_system" '.assets[$system] // empty' "$config")"

    if [[ -z $asset_name ]]; then
        echo "$package does not support $current_system" >&2
        return 1
    fi

    if [[ -z $tag_pattern ]]; then
        release="$(github_api "repos/$repository/releases/latest")"
        asset="$(
            jq --arg name "$asset_name" \
                '.assets[] | select(.name == $name)' \
                <<<"$release"
        )"
    else
        release="$(
            github_api "repos/$repository/releases?per_page=100" |
                jq --compact-output --arg pattern "$tag_pattern" \
                    'first(.[] | select(.draft == false and (.tag_name | contains($pattern)))) // empty'
        )"

        if [[ -z $release ]]; then
            echo "No release matching $tag_pattern found for $repository" >&2
            return 1
        fi

        asset="$(
            jq --arg pattern "$asset_name" \
                '.assets[] | select(.name | test($pattern))' \
                <<<"$release"
        )"
    fi

    if [[ -z $asset ]]; then
        echo "No matching asset found for $package on $current_system" >&2
        return 1
    fi

    version="$(jq --raw-output '.tag_name | sub("^v"; "")' <<<"$release")"
    url="$(jq --raw-output .browser_download_url <<<"$asset")"
    digest="$(jq --raw-output '.digest // empty' <<<"$asset")"

    if [[ -n $digest ]]; then
        hash="$(
            nix hash convert \
                --hash-algo sha256 \
                --to sri \
                "${digest#sha256:}"
        )"
    else
        hash="$(
            nix store prefetch-file --json "$url" |
                jq --raw-output .hash
        )"
    fi

    temporary="$(mktemp "$sources.XXXXXX")"
    trap 'rm -f "$temporary"' RETURN
    jq --indent 4 \
        --arg system "$current_system" \
        --arg version "$version" \
        --arg url "$url" \
        --arg hash "$hash" \
        '.platforms[$system] = {
            version: $version,
            url: $url,
            hash: $hash
        }' \
        "$sources" >"$temporary"
    mv "$temporary" "$sources"
    trap - RETURN

    echo "Building $package..."
    nix build "path:$root#$package" --no-link
}

if (($# > 0)); then
    for package in "$@"; do
        update_package "$package"
    done
else
    for config in "$root"/packages/*/update.json; do
        package="$(basename "$(dirname "$config")")"
        update_package "$package"
    done
fi
