#!/usr/bin/env bash
# winpicker.sh — show current session windows via choose-tree
SESSION=$(tmux display-message -p '#S')
tmux choose-tree -Zw -f "#{==:#{session_name},$SESSION}"
