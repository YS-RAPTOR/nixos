#!/usr/bin/env bash

divider='---------'

choose() {
    wofi --dmenu --prompt "$1"
}

powered() {
    bluetoothctl show | grep --quiet 'Powered: yes'
}

device_info() {
    bluetoothctl info "$1"
}

device_property() {
    device_info "$1" | grep --max-count=1 "$2:" | cut --delimiter=' ' --fields=2-
}

device_menu() {
    local mac=$1
    local name connected paired trusted choice

    while true; do
        name=$(device_property "$mac" Alias)
        connected=$(device_property "$mac" Connected)
        paired=$(device_property "$mac" Paired)
        trusted=$(device_property "$mac" Trusted)

        choice=$(printf '%s\n' \
            "Connected: $connected" \
            "Paired: $paired" \
            "Trusted: $trusted" \
            "$divider" \
            Back | choose "$name")

        case "$choice" in
        "Connected: yes") bluetoothctl disconnect "$mac" ;;
        "Connected: no") bluetoothctl connect "$mac" ;;
        "Paired: yes")
            bluetoothctl remove "$mac"
            return
            ;;
        "Paired: no") bluetoothctl pair "$mac" ;;
        "Trusted: yes") bluetoothctl untrust "$mac" ;;
        "Trusted: no") bluetoothctl trust "$mac" ;;
        Back | "") return ;;
        esac
    done
}

while true; do
    if powered; then
        power='Power: on'
        scanning=$(bluetoothctl show | grep --quiet 'Discovering: yes' && printf on || printf off)
        pairable=$(bluetoothctl show | grep --quiet 'Pairable: yes' && printf on || printf off)
        discoverable=$(bluetoothctl show | grep --quiet 'Discoverable: yes' && printf on || printf off)
        devices=$(bluetoothctl devices)

        choice=$(
            {
                printf '%s\n' "$devices"
                printf '%s\n' "$divider" "$power" "Scan: $scanning" "Pairable: $pairable" \
                    "Discoverable: $discoverable" Exit
            } | choose Bluetooth
        )
    else
        power='Power: off'
        choice=$(printf '%s\n' "$power" Exit | choose Bluetooth)
    fi

    case "$choice" in
    'Power: on') bluetoothctl power off ;;
    'Power: off')
        if rfkill list bluetooth | grep --quiet 'blocked: yes'; then
            rfkill unblock bluetooth
            sleep 1
        fi
        bluetoothctl power on
        ;;
    'Scan: on') bluetoothctl scan off ;;
    'Scan: off') bluetoothctl --timeout 5 scan on ;;
    'Pairable: on') bluetoothctl pairable off ;;
    'Pairable: off') bluetoothctl pairable on ;;
    'Discoverable: on') bluetoothctl discoverable off ;;
    'Discoverable: off') bluetoothctl discoverable on ;;
    Device\ *)
        mac=${choice#Device }
        mac=${mac%% *}
        device_menu "$mac"
        ;;
    Exit | "") exit ;;
    esac
done
