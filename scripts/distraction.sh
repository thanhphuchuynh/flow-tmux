#!/usr/bin/env bash
# distraction.sh — Log distractions during focus sessions

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

log_distraction() {
    local msg="$1"
    [ -z "$msg" ] && { flow_message "info" "󰅖 Empty distraction note"; return; }
    ensure_stats_dir
    local status
    status=$(read_state "status" "idle")
    local phase="$status"
    [ "$status" = "paused" ] && phase=$(read_state "phase_before_pause" "work")
    echo "$(date +%Y-%m-%dT%H:%M:%S),$phase,$msg" >> "$FLOW_DISTRACTION_FILE"
    flow_message "info" "󰍉 Distraction logged: $msg"
}

prompt_distraction() {
    tmux command-prompt -p "󰍉 Distraction:" \
        "run-shell \"$CURRENT_DIR/distraction.sh log '%1'\""
}

show_distractions() {
    if [ ! -f "$FLOW_DISTRACTION_FILE" ]; then
        flow_message "info" "No distractions logged yet"
        return
    fi
    local today
    today=$(date +%Y-%m-%d)
    local content="━━━ 󰍉 Today's Distractions ━━━\n\n"
    local count=0
    while IFS=',' read -r timestamp phase msg; do
        if [[ "$timestamp" == "$today"* ]]; then
            local time="${timestamp#*T}"
            time="${time%:*}"  # HH:MM
            content+="  $time [$phase] $msg\n"
            count=$(( count + 1 ))
        fi
    done < "$FLOW_DISTRACTION_FILE"
    [ "$count" -eq 0 ] && content+="  (none)\n"
    content+="\n━━━ Total: $count ━━━\n"
    tmux display-popup -w 50 -h 16 -T " 󰍉 Distractions " \
        -E "printf '$content' | less -R"
}

case "${1:-}" in
    log)    log_distraction "${2:-}" ;;
    prompt) prompt_distraction ;;
    show)   show_distractions ;;
    *)      echo "Usage: distraction.sh {log <msg>|prompt|show}"; exit 1 ;;
esac
