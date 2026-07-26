#!/usr/bin/env bash

cache_dir=${XDG_CACHE_HOME:-"$HOME/.cache"}/colorpicker
colors_file=$cache_dir/colors
mkdir -p "$cache_dir"
touch "$colors_file"

if [ "${1:-}" = "--json" ]; then
    mapfile -t colors < <(grep -v '^$' "$colors_file")
    current=${colors[0]:-}
    tooltip='<b>   COLORS</b>'

    for color in "${colors[@]}"; do
        tooltip="$tooltip\n\n   <b>$color</b>  <span color='$color'></span>"
    done

    if [ -n "$current" ]; then
        text="<span color='$current'></span>"
    else
        text=''
    fi

    jq --compact-output --null-input --arg text "$text" --arg tooltip "$tooltip" '{ $text, $tooltip }'
    exit
fi

pkill --exact hyprpicker 2>/dev/null || true
color=$(hyprpicker || true)
[ -n "$color" ] || exit

printf '%s' "$color" | wl-copy
notify-send --app-name "Color Picker" "Copied $color"

temporary=$(mktemp "$cache_dir/colors.XXXXXX")
{
    printf '%s\n' "$color"
    grep -Fvx "$color" "$colors_file" || true
} | grep -v '^$' | head -n 10 >"$temporary"
mv "$temporary" "$colors_file"

pkill -RTMIN+1 --exact waybar 2>/dev/null || true
