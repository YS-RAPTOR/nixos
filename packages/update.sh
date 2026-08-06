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

npm_registry_metadata() {
    local package_name="$1"
    local encoded_name

    encoded_name="$(jq --null-input --raw-output --arg name "$package_name" '$name | @uri')"
    curl -fsSL "https://registry.npmjs.org/$encoded_name"
}

build_package() {
    local package="$1"

    echo "Building $package..."
    nix build "path:$root#$package" --no-link
}

update_github_release() {
    local package="$1"
    local config="$2"
    local sources="$3"
    local repository tag_pattern asset_name release asset version url digest hash temporary

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
}

prefetch_npm_dependencies() (
    set -euo pipefail

    local url="$1"
    local dependency_integrities="$2"
    local temporary_directory

    temporary_directory="$(mktemp -d)"
    trap 'rm -rf "$temporary_directory"' EXIT

    curl -fsSL "$url" | tar -xz -C "$temporary_directory"
    jq --argjson integrities "$dependency_integrities" '
        reduce ($integrities | to_entries[]) as $dependency (
            .;
            .packages["node_modules/\($dependency.key)"].integrity = $dependency.value
        )
    ' \
        "$temporary_directory/package/npm-shrinkwrap.json" \
        >"$temporary_directory/npm-shrinkwrap.patched.json"

    nix run nixpkgs#prefetch-npm-deps -- \
        "$temporary_directory/npm-shrinkwrap.patched.json"
)

update_npm() {
    local package="$1"
    local config="$2"
    local sources="$3"
    local package_name metadata version manifest url hash
    local dependency dependency_metadata integrity
    local dependency_integrities='{}'
    local npm_deps_hash temporary

    package_name="$(jq --raw-output .package "$config")"
    metadata="$(npm_registry_metadata "$package_name")"
    version="$(jq --raw-output '.["dist-tags"].latest' <<<"$metadata")"
    manifest="$(jq --compact-output --arg version "$version" '.versions[$version]' <<<"$metadata")"
    url="$(jq --raw-output .dist.tarball <<<"$manifest")"
    hash="$(jq --raw-output .dist.integrity <<<"$manifest")"

    while IFS= read -r dependency; do
        dependency_metadata="$(npm_registry_metadata "$dependency")"
        integrity="$(
            jq --raw-output --arg version "$version" \
                '.versions[$version].dist.integrity // empty' \
                <<<"$dependency_metadata"
        )"

        if [[ -z $integrity ]]; then
            echo "No $dependency@$version package found for $package_name@$version" >&2
            return 1
        fi

        dependency_integrities="$(
            jq --arg dependency "$dependency" --arg integrity "$integrity" \
                '. + {($dependency): $integrity}' \
                <<<"$dependency_integrities"
        )"
    done < <(jq --raw-output '.integrityDependencies[]' "$config")

    npm_deps_hash="$(prefetch_npm_dependencies "$url" "$dependency_integrities")"

    temporary="$(mktemp "$sources.XXXXXX")"
    jq --null-input --indent 4 \
        --arg version "$version" \
        --arg url "$url" \
        --arg hash "$hash" \
        --arg npmDepsHash "$npm_deps_hash" \
        --argjson dependencyIntegrities "$dependency_integrities" \
        '{
            version: $version,
            url: $url,
            hash: $hash,
            npmDepsHash: $npmDepsHash,
            dependencyIntegrities: $dependencyIntegrities
        }' >"$temporary"
    mv "$temporary" "$sources"

    echo "Updated $package from $package_name@$version"
}

update_package() {
    local package="$1"
    local config="$root/packages/$package/update.json"
    local sources="$root/packages/$package/sources.json"
    local update_type

    if [[ ! -f $config ]]; then
        echo "No update configuration for package: $package" >&2
        return 1
    fi
    if [[ ! -f $sources ]]; then
        echo "No sources file for package: $package" >&2
        return 1
    fi

    update_type="$(jq --raw-output '.type // empty' "$config")"
    echo "Updating $package ($update_type)..."

    case "$update_type" in
    github-release)
        update_github_release "$package" "$config" "$sources"
        ;;
    npm)
        update_npm "$package" "$config" "$sources"
        ;;
    "")
        echo "Missing update type for package: $package" >&2
        return 1
        ;;
    *)
        echo "Unsupported update type for $package: $update_type" >&2
        return 1
        ;;
    esac

    build_package "$package"
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
