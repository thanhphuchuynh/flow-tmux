#!/usr/bin/env bash
# notifications.sh — Notification center (show, clear, count, mark_read, status)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

show_notifications() {
    if [ ! -f "$FLOW_NOTIFICATIONS_FILE" ]; then
        tmux display-message "No notifications yet"
        return
    fi
    local content="━━━ 󰂚 Notifications ━━━\n\n"
    local count=0
    # Show last 30 lines
    local lines
    lines=$(tail -30 "$FLOW_NOTIFICATIONS_FILE")
    while IFS=',' read -r timestamp type msg; do
        [ -z "$timestamp" ] && continue
        local time="${timestamp#*T}"
        time="${time%:*}"  # HH:MM
        local date="${timestamp%%T*}"
        date="${date#*-}"  # MM-DD
        content+="  $date $time [$type] $msg\n"
        count=$(( count + 1 ))
    done <<< "$lines"
    [ "$count" -eq 0 ] && content+="  (none)\n"
    content+="\n━━━ Showing last $count ━━━\n"

    # Mark as read
    mark_read

    tmux display-popup -w 60 -h 22 -T " 󰂚 Notifications " \
        -E "printf '$content' | less -R"
}

clear_notifications() {
    rm -f "$FLOW_NOTIFICATIONS_FILE" "$FLOW_NOTIFICATIONS_READ"
    tmux display-message "󰂚 Notifications cleared"
}

count_unread() {
    [ -f "$FLOW_NOTIFICATIONS_FILE" ] || { echo 0; return; }
    local last_read=""
    [ -f "$FLOW_NOTIFICATIONS_READ" ] && last_read=$(cat "$FLOW_NOTIFICATIONS_READ")
    if [ -z "$last_read" ]; then
        wc -l < "$FLOW_NOTIFICATIONS_FILE" | tr -d ' '
        return
    fi
    local count=0
    while IFS=',' read -r timestamp _; do
        [ -z "$timestamp" ] && continue
        if [[ "$timestamp" > "$last_read" ]]; then
            count=$(( count + 1 ))
        fi
    done < "$FLOW_NOTIFICATIONS_FILE"
    echo "$count"
}

mark_read() {
    ensure_stats_dir
    date +%Y-%m-%dT%H:%M:%S > "$FLOW_NOTIFICATIONS_READ"
}

show_status() {
    [ "$(get_notifications_enabled)" = "on" ] || return
    local unread
    unread=$(count_unread)
    [ "$unread" -gt 0 ] && echo " 󰂚${unread}"
}

case "${1:-}" in
    show)      show_notifications ;;
    clear)     clear_notifications ;;
    count)     count_unread ;;
    mark_read) mark_read ;;
    status)    show_status ;;
    *)         echo "Usage: notifications.sh {show|clear|count|mark_read|status}"; exit 1 ;;
esac
