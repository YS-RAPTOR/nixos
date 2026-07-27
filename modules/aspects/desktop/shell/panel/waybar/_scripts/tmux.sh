#!/usr/bin/env bash

name=${USER:-user}

while true; do
    prefix_state=$(tmux display-message -p '#{client_prefix}' 2>/dev/null || true)
    if [ "$prefix_state" = 1 ]; then
        class=active
    else
        class=inactive
    fi

    jq --compact-output --null-input --arg text "$name" --arg class "$class" '{ $text, $class }'
    sleep 0.1
done
