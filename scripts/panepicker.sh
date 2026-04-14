#!/usr/bin/env bash
# panepicker.sh — list panes in current window only
SESSION=$(tmux display-message -p '#S')
WINDOW_IDX=$(tmux display-message -p '#I')
tmux choose-tree -Z \
    -f "#{&&:#{==:#{session_name},$SESSION},#{==:#{window_index},$WINDOW_IDX}}"
