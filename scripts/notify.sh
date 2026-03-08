#!/usr/bin/env bash
# notify.sh — Notifications (display-message + bell + OS + tick sound)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

send_notification() {
    local phase="$1"
    local title message

    if [ "$phase" = "work" ]; then
        title="󱎫 Focus Session Complete"
        message="Great work! Time for a break."
    else
        title="󰅶 Break Over"
        message="Ready to focus again?"
    fi

    flow_message "timer" "$title — $message"

    # Terminal bell
    if [ "$(get_bell_enabled)" = "on" ]; then
        local panes
        panes=$(tmux list-panes -F '#{pane_id}' 2>/dev/null)
        for pane in $panes; do
            tmux send-keys -t "$pane" "" 2>/dev/null || true
        done
    fi

    # OS notifications
    if [ "$(get_notify_enabled)" = "on" ]; then
        local sound
        sound=$(get_sound)
        if command -v osascript &>/dev/null; then
            osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null &
        elif command -v notify-send &>/dev/null; then
            notify-send "$title" "$message" 2>/dev/null &
        fi
    fi
}

if [ -n "${1:-}" ]; then
    send_notification "$1"
fi
