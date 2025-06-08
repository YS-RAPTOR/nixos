#!/usr/bin/env bash

panes_count=$(tmux list-panes | wc -l)
# Split the pane vertically if there is only one pane
did_split=0
if [ $panes_count -eq 1 ]; then
	tmux split-window -v -c "#{pane_current_path}"
	did_split=1
fi

is_zoomed=$(tmux display-message -p "#{window_zoomed_flag}")
active_pane=$(tmux list-panes -f "#{pane_active}" -F "#P")
bottom_panes=$(tmux list-panes -f "#{&&:#{pane_at_bottom},#{!=:#{pane_at_bottom},#{pane_active}}}" -F "#P")
first_bottom_pane=$(echo $bottom_panes | cut -d ' ' -f 1)

if [ $is_zoomed -eq 1 ]; then
	tmux resize-pane -Z
fi

if [ $active_pane -eq 1 ]; then
	# Check if the active pane is the first pane (Main Pane)
	tmux select-pane -t $first_bottom_pane
elif [ $did_split -eq 0 ]; then
	# Else Move to the main pane
	tmux select-pane -t 1
fi
tmux resize-pane -Z
