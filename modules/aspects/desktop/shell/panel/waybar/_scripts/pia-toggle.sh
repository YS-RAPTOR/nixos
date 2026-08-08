set -euo pipefail

state=$(pia-vpn status --waybar | jq -r '.alt')
if [[ $state == setup-required ]]; then
    ghostty -e pia-vpn credentials set >/dev/null 2>&1 &
else
    pia-vpn toggle
fi
