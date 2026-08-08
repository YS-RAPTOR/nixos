set -euo pipefail

locations=$(pia-vpn locations --json)
default_name=$(jq -r --arg id "$PIA_DEFAULT_REGION" '.[] | select(.id == $id) | .name' <<<"$locations")
default_name=${default_name:-$PIA_DEFAULT_REGION}

selection=$(
    {
        printf 'Use configured default — %s\t%s\n' "$default_name" "$PIA_DEFAULT_REGION"
        jq -r '.[] | "\(.name)\t\(.id)"' <<<"$locations"
    } | wofi --dmenu --prompt 'PIA location'
) || exit 0

region=${selection##*$'\t'}
if [[ $selection == 'Use configured default — '* ]]; then
    pia-vpn location reset
else
    pia-vpn location set "$region"
fi
