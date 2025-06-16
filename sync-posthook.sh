#!/bin/sh

# hyprland
pgrep Hyprland &> /dev/null && echo "Reloading hyprland" && hyprctl reload &> /dev/null;
pgrep hyprpaper &> /dev/null && echo "Reapplying background via hyprpaper" && pkill hyprpaper && echo "Running hyprpaper" && hyprpaper &> /dev/null & disown;
