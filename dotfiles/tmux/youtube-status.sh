#!/usr/bin/env bash

tmux_option_or_fallback() {
    local option_value
    option_value="$(tmux show-option -gqv "$1")"
    if [ -z "$option_value" ]; then
        option_value="$2"
    fi
    echo "$option_value"
}

# Get server response

server_url=$(tmux_option_or_fallback "@youtube-status-server" "localhost:2003")
server_response=$(curl --connect-timeout 0.01 $server_url)

if [ -z "$server_response" ]; then
    exit 0
fi

# Get music info
title=$(echo $server_response | jq -r '.title')
artist=$(echo $server_response | jq -r '.artist')

$title_length=${#title}
$artist_length=${#artist}

status=$(echo $server_response | jq -r '.status')

progress=$(echo $server_response | jq -r '.progress')
duration=$(echo $server_response | jq -r '.duration')

if [ -z "$title" ]; then
    exit 0
fi

if [ "$status" = "playing" ]; then
    status=""
else
    status=""
fi

len_title=7
len_artist=8

if ((title_length < len_title)); then
    len_title=$((len_title + len_artist - artist_length))
fi
5 +

if ((artist_length < len_artist)); then
    len_artist=$((len_artist + len_title - title_length))
fi

function surround() {
    music_status="#[bg=#15151d, fg=#f7768e]#[fg=#15151d, bg=#f7768e]$status ${title:0:len_title} by ${artist:0:len_artist} | $progress/$duration"
}

surround
echo "$music_status"
