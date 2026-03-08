#!/usr/bin/env bash
# helpers.sh — tmux option helpers and state management

FLOW_STATS_DIR="$HOME/.cache/flow-tmux"
FLOW_STATS_FILE="$FLOW_STATS_DIR/stats.csv"
FLOW_TASKS_FILE="$FLOW_STATS_DIR/tasks.tsv"
FLOW_SUBTASKS_FILE="$FLOW_STATS_DIR/subtasks.tsv"
FLOW_DISTRACTION_FILE="$FLOW_STATS_DIR/distractions.csv"
FLOW_PROJECTS_FILE="$FLOW_STATS_DIR/projects.conf"
FLOW_NOTIFICATIONS_FILE="$FLOW_STATS_DIR/notifications.csv"
FLOW_NOTIFICATIONS_READ="$FLOW_STATS_DIR/notifications_last_read"

# Session-aware state directory
_get_state_dir() {
    local base="/tmp/flow_tmux"
    if [ "$(tmux show-option -gqv "@flow_session_aware")" = "on" ]; then
        local session_name
        session_name=$(tmux display-message -p '#S' 2>/dev/null || echo "default")
        echo "$base/$session_name"
    else
        echo "$base"
    fi
}
FLOW_STATE_DIR="$(_get_state_dir)"

ensure_state_dir() { mkdir -p "$FLOW_STATE_DIR"; }
ensure_stats_dir() { mkdir -p "$FLOW_STATS_DIR"; }

# tmux option helpers
get_tmux_option() {
    local option="$1" default_value="$2"
    local value
    value=$(tmux show-option -gqv "$option")
    [ -z "$value" ] && echo "$default_value" || echo "$value"
}

set_tmux_option() { tmux set-option -gq "$1" "$2"; }

# State read/write
read_state() {
    local file="$FLOW_STATE_DIR/$1"
    [ -f "$file" ] && cat "$file" || echo "$2"
}

write_state() {
    ensure_state_dir
    printf '%s' "$2" > "$FLOW_STATE_DIR/$1"
}

clear_state() {
    rm -f "$FLOW_STATE_DIR/status" "$FLOW_STATE_DIR/start_time" \
          "$FLOW_STATE_DIR/paused_at" "$FLOW_STATE_DIR/time_paused" \
          "$FLOW_STATE_DIR/phase_before_pause"
}

clear_goal() {
    rm -f "$FLOW_STATE_DIR/goal" "$FLOW_STATE_DIR/current_task_id"
}

# ── Core config ──
get_work_duration()      { get_tmux_option "@flow_work_duration" "25"; }
get_break_duration()     { get_tmux_option "@flow_break_duration" "5"; }
get_long_break_duration(){ get_tmux_option "@flow_long_break_duration" "15"; }
get_long_break_after()   { get_tmux_option "@flow_long_break_after" "4"; }
get_bell_enabled()       { get_tmux_option "@flow_bell" "on"; }
get_notify_enabled()     { get_tmux_option "@flow_notify" "on"; }
get_sound()              { get_tmux_option "@flow_sound" "Glass"; }

# ── Feature toggles (all default off) ──
# Productivity
get_auto_start()         { get_tmux_option "@flow_auto_start" "off"; }
get_daily_goal()         { get_tmux_option "@flow_daily_goal" "0"; }  # 0=disabled, N=target
get_streak_enabled()     { get_tmux_option "@flow_streak" "off"; }
get_distraction_enabled(){ get_tmux_option "@flow_distraction" "off"; }
# UX
get_colors_enabled()     { get_tmux_option "@flow_colors" "off"; }
get_progress_bar_enabled(){ get_tmux_option "@flow_progress_bar" "off"; }
get_tick_enabled()       { get_tmux_option "@flow_tick" "off"; }
get_format_template()    { get_tmux_option "@flow_format" ""; }  # empty=default
# Tasks
get_priority_enabled()   { get_tmux_option "@flow_task_priority" "off"; }
get_tracking_enabled()   { get_tmux_option "@flow_task_tracking" "off"; }
get_subtasks_enabled()   { get_tmux_option "@flow_subtasks" "off"; }
get_recurring_enabled()  { get_tmux_option "@flow_recurring" "off"; }
# Data
get_weekly_report_enabled(){ get_tmux_option "@flow_weekly_report" "off"; }
get_export_enabled()     { get_tmux_option "@flow_export" "off"; }
get_heatmap_enabled()    { get_tmux_option "@flow_heatmap" "off"; }
# Session
get_session_aware()      { get_tmux_option "@flow_session_aware" "off"; }
# Projects & Notifications
get_projects_enabled()      { get_tmux_option "@flow_projects" "off"; }
get_notifications_enabled() { get_tmux_option "@flow_notifications" "off"; }

# ── Helpers ──
now() { date +%s; }

# Count today's completed work sessions from stats
count_today_sessions() {
    local today
    today=$(date +%Y-%m-%d)
    local count=0
    [ -f "$FLOW_STATS_FILE" ] || { echo 0; return; }
    while IFS=',' read -r timestamp _ type _; do
        if [ "$type" = "work" ] && [[ "$timestamp" == "$today"* ]]; then
            count=$(( count + 1 ))
        fi
    done < "$FLOW_STATS_FILE"
    echo "$count"
}

# Calculate streak (consecutive days with work sessions)
calculate_streak() {
    [ -f "$FLOW_STATS_FILE" ] || { echo 0; return; }
    local -a days=()
    while IFS=',' read -r timestamp _ type _; do
        if [ "$type" = "work" ]; then
            days+=("${timestamp%%T*}")
        fi
    done < "$FLOW_STATS_FILE"
    # Unique sorted days
    local -a unique_days
    IFS=$'\n' read -r -d '' -a unique_days < <(printf '%s\n' "${days[@]}" | sort -u -r && printf '\0')
    local streak=0
    local check_date
    check_date=$(date +%Y-%m-%d)
    for day in "${unique_days[@]}"; do
        if [ "$day" = "$check_date" ]; then
            streak=$(( streak + 1 ))
            # Go back one day
            if date -v-1d +%Y-%m-%d &>/dev/null 2>&1; then
                check_date=$(date -j -f "%Y-%m-%d" "$check_date" -v-1d +%Y-%m-%d 2>/dev/null)
            else
                check_date=$(date -d "$check_date - 1 day" +%Y-%m-%d 2>/dev/null)
            fi
        elif [[ "$day" < "$check_date" ]]; then
            break
        fi
    done
    echo "$streak"
}

# ── Notification-aware message display ──
flow_message() {
    local type="${1:-info}" message="$2"
    tmux display-message "$message"
    if [ "$(get_notifications_enabled)" = "on" ]; then
        ensure_stats_dir
        echo "$(date +%Y-%m-%dT%H:%M:%S),$type,$message" >> "$FLOW_NOTIFICATIONS_FILE"
    fi
}
