#!/usr/bin/env bash
# flow.sh — Core timer logic

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

start_work() {
    ensure_state_dir
    write_state "status" "work"
    write_state "start_time" "$(now)"
    write_state "time_paused" "0"
    rm -f "$FLOW_STATE_DIR/paused_at" "$FLOW_STATE_DIR/phase_before_pause"
    flow_message "timer" "󱎫 Focus session started ($(get_work_duration) min)"
}

start_work_with_goal() {
    tmux command-prompt -p "󰀘 What will you focus on?" \
        "run-shell \"$CURRENT_DIR/flow.sh _set_goal_and_start '%1'\""
}

_set_goal_and_start() {
    local goal="$1"
    ensure_state_dir
    [ -n "$goal" ] && write_state "goal" "$goal" || rm -f "$FLOW_STATE_DIR/goal"
    start_work
}

start_break() {
    local session_count
    session_count=$(read_state "session_count" "0")
    local long_break_after
    long_break_after=$(get_long_break_after)
    local break_duration break_type
    if [ "$session_count" -ge "$long_break_after" ] && [ "$session_count" -gt 0 ] && [ $((session_count % long_break_after)) -eq 0 ]; then
        break_duration=$(get_long_break_duration)
        break_type="long"
    else
        break_duration=$(get_break_duration)
        break_type="short"
    fi
    ensure_state_dir
    write_state "status" "break"
    write_state "start_time" "$(now)"
    write_state "time_paused" "0"
    rm -f "$FLOW_STATE_DIR/paused_at" "$FLOW_STATE_DIR/phase_before_pause"
    [ "$break_type" = "long" ] && flow_message "timer" "󰅶 Long break started ($break_duration min)" \
                               || flow_message "timer" "󰅶 Break started ($break_duration min)"
}

pause_timer() {
    local status
    status=$(read_state "status" "idle")
    if [ "$status" = "work" ] || [ "$status" = "break" ]; then
        write_state "phase_before_pause" "$status"
        write_state "paused_at" "$(now)"
        write_state "status" "paused"
        flow_message "timer" "󰏤 Timer paused"
    fi
}

resume_timer() {
    local status
    status=$(read_state "status" "idle")
    if [ "$status" = "paused" ]; then
        local paused_at
        paused_at=$(read_state "paused_at" "$(now)")
        local current_paused
        current_paused=$(read_state "time_paused" "0")
        write_state "time_paused" "$(( current_paused + $(now) - paused_at ))"
        local phase
        phase=$(read_state "phase_before_pause" "work")
        write_state "status" "$phase"
        rm -f "$FLOW_STATE_DIR/paused_at" "$FLOW_STATE_DIR/phase_before_pause"
        flow_message "timer" "󰐊 Timer resumed"
    fi
}

toggle() {
    local status
    status=$(read_state "status" "idle")
    case "$status" in
        idle)       start_work_with_goal ;;
        paused)     resume_timer ;;
        work|break) pause_timer ;;
    esac
}

skip() {
    local status
    status=$(read_state "status" "idle")
    [ "$status" = "paused" ] && status=$(read_state "phase_before_pause" "work")
    case "$status" in
        work)  cancel_timer_silent; start_break ;;
        break) cancel_timer_silent; start_work ;;
        *)     start_work ;;
    esac
    flow_message "timer" "󰒭 Skipped to next phase"
}

cancel_timer() {
    clear_state
    clear_goal
    write_state "status" "idle"
    flow_message "timer" "󰓛 Timer cancelled"
}

cancel_timer_silent() {
    clear_state
    write_state "status" "idle"
}

case "${1:-}" in
    start_work)           start_work ;;
    start_work_with_goal) start_work_with_goal ;;
    start_break)          start_break ;;
    toggle)               toggle ;;
    pause)                pause_timer ;;
    resume)               resume_timer ;;
    skip)                 skip ;;
    cancel)               cancel_timer ;;
    _set_goal_and_start)  _set_goal_and_start "${2:-}" ;;
    *)
        echo "Usage: flow.sh {start_work|start_work_with_goal|start_break|toggle|pause|resume|skip|cancel}"
        exit 1
        ;;
esac
