#!/usr/bin/env bash
# status.sh — Status bar output, called on each status-interval tick

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# ── Recurring task daily reset ──
check_recurring_reset() {
    [ "$(get_recurring_enabled)" = "on" ] || return
    local today
    today=$(date +%Y-%m-%d)
    local last_reset
    last_reset=$(read_state "last_recurring_reset" "")
    [ "$last_reset" = "$today" ] && return
    write_state "last_recurring_reset" "$today"
    # Reset recurring tasks to todo
    [ -f "$FLOW_TASKS_FILE" ] || return
    local tmpfile
    tmpfile=$(mktemp)
    while IFS=$'\t' read -r line; do
        local id status title created priority pomodoros recurring
        IFS=$'\t' read -r id status title created priority pomodoros recurring <<< "$line"
        if [ "$recurring" = "daily" ] && [ "$status" = "done" ]; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "todo" "$title" "$created" "$priority" "0" "$recurring"
        else
            echo "$line"
        fi
    done < "$FLOW_TASKS_FILE" > "$tmpfile"
    mv "$tmpfile" "$FLOW_TASKS_FILE"
}

get_duration_seconds() {
    local status="$1"
    local session_count
    session_count=$(read_state "session_count" "0")
    local long_break_after
    long_break_after=$(get_long_break_after)
    case "$status" in
        work)  echo $(( $(get_work_duration) * 60 )) ;;
        break)
            if [ "$session_count" -gt 0 ] && [ $((session_count % long_break_after)) -eq 0 ]; then
                echo $(( $(get_long_break_duration) * 60 ))
            else
                echo $(( $(get_break_duration) * 60 ))
            fi ;;
    esac
}

format_time() {
    local s="$1"
    [ "$s" -lt 0 ] && s=0
    printf "%02d:%02d" $(( s / 60 )) $(( s % 60 ))
}

format_goal() {
    local goal
    goal=$(read_state "goal" "")
    if [ -n "$goal" ]; then
        [ ${#goal} -gt 20 ] && goal="${goal:0:18}.."
        echo " 󰀘 $goal"
    fi
}

format_progress_bar() {
    local elapsed="$1" total="$2"
    [ "$total" -le 0 ] && { echo ""; return; }
    local width=8
    local filled=$(( elapsed * width / total ))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

format_daily_progress() {
    local target
    target=$(get_daily_goal)
    [ "$target" = "0" ] && return
    local done_count
    done_count=$(count_today_sessions)
    echo " $done_count/$target"
}

format_streak() {
    [ "$(get_streak_enabled)" = "on" ] || return
    local streak
    streak=$(calculate_streak)
    [ "$streak" -gt 0 ] && echo " 󰈸${streak}d"
}

compute_remaining() {
    local status="$1"
    local start_time
    start_time=$(read_state "start_time" "0")
    local time_paused
    time_paused=$(read_state "time_paused" "0")
    local duration
    duration=$(get_duration_seconds "$status")
    echo $(( duration - ($(now) - start_time - time_paused) ))
}

compute_elapsed() {
    local start_time
    start_time=$(read_state "start_time" "0")
    local time_paused
    time_paused=$(read_state "time_paused" "0")
    echo $(( $(now) - start_time - time_paused ))
}

# Apply color wrapping
colorize() {
    local text="$1" phase="$2"
    [ "$(get_colors_enabled)" != "on" ] && { echo "$text"; return; }
    local color
    case "$phase" in
        work)   color="#[fg=#e06c75]" ;;   # red
        break)  color="#[fg=#98c379]" ;;   # green
        paused) color="#[fg=#e5c07b]" ;;   # yellow
    esac
    echo "${color}${text}#[fg=default]"
}

# Build output using custom format or default
build_output() {
    local icon="$1" time_str="$2" phase="$3" remaining="$4" duration="$5"
    local template
    template=$(get_format_template)

    local goal_str
    goal_str=$(format_goal)
    local daily_str
    daily_str=$(format_daily_progress)
    local streak_str
    streak_str=$(format_streak)
    local bar_str=""

    if [ "$(get_progress_bar_enabled)" = "on" ] && [ "$duration" -gt 0 ]; then
        local elapsed=$(( duration - remaining ))
        bar_str=" $(format_progress_bar "$elapsed" "$duration")"
    fi

    # Notification badge
    local notif_str=""
    if [ "$(get_notifications_enabled)" = "on" ]; then
        notif_str=$("$CURRENT_DIR/notifications.sh" status)
    fi

    local output
    if [ -n "$template" ]; then
        output="$template"
        output="${output//\{icon\}/$icon}"
        output="${output//\{time\}/$time_str}"
        output="${output//\{goal\}/$goal_str}"
        output="${output//\{bar\}/$bar_str}"
        output="${output//\{daily\}/$daily_str}"
        output="${output//\{streak\}/$streak_str}"
        output="${output//\{notif\}/$notif_str}"
    else
        output="${icon} ${time_str}${bar_str}${goal_str}${daily_str}${streak_str}${notif_str}"
    fi

    colorize "$output" "$phase"
}

# ── Tick sound (last 5 minutes warning) ──
check_tick() {
    [ "$(get_tick_enabled)" = "on" ] || return
    local remaining="$1"
    [ "$remaining" -gt 300 ] || [ "$remaining" -le 0 ] && return
    # Tick once per minute: only when remaining is exactly divisible by 60 (±1 second tolerance)
    local mod=$(( remaining % 60 ))
    if [ "$mod" -le 1 ] || [ "$mod" -ge 59 ]; then
        if command -v afplay &>/dev/null; then
            afplay /System/Library/Sounds/Tink.aiff &>/dev/null &
        fi
    fi
}

handle_completion() {
    local status="$1"
    "$CURRENT_DIR/stats.sh" log "$status"
    "$CURRENT_DIR/notify.sh" "$status"

    if [ "$status" = "work" ]; then
        # Auto-complete current task & increment pomodoro count
        local task_id
        task_id=$(read_state "current_task_id" "")
        if [ -n "$task_id" ]; then
            "$CURRENT_DIR/tasks.sh" complete
            [ "$(get_tracking_enabled)" = "on" ] && "$CURRENT_DIR/tasks.sh" _inc_pomodoro "$task_id"
        fi

        local count
        count=$(read_state "session_count" "0")
        write_state "session_count" "$(( count + 1 ))"
        clear_state
        write_state "status" "break"
        write_state "start_time" "$(now)"
        write_state "time_paused" "0"
        write_state "session_count" "$(( count + 1 ))"
    else
        # Break done
        clear_state
        clear_goal
        if [ "$(get_auto_start)" = "on" ]; then
            write_state "status" "work"
            write_state "start_time" "$(now)"
            write_state "time_paused" "0"
        else
            write_state "status" "idle"
        fi
    fi
}

main() {
    check_recurring_reset

    local status
    status=$(read_state "status" "idle")

    case "$status" in
        idle)
            echo ""
            ;;
        paused)
            local phase
            phase=$(read_state "phase_before_pause" "work")
            local paused_at
            paused_at=$(read_state "paused_at" "$(now)")
            local start_time
            start_time=$(read_state "start_time" "0")
            local time_paused
            time_paused=$(read_state "time_paused" "0")
            local duration
            duration=$(get_duration_seconds "$phase")
            local elapsed=$(( paused_at - start_time - time_paused ))
            local remaining=$(( duration - elapsed ))
            build_output "󰏤" "$(format_time "$remaining")" "paused" "$remaining" "$duration"
            ;;
        work)
            local remaining
            remaining=$(compute_remaining "work")
            if [ "$remaining" -le 0 ]; then
                handle_completion "work"
                local new_status
                new_status=$(read_state "status" "idle")
                if [ "$new_status" = "break" ]; then
                    local r
                    r=$(compute_remaining "break")
                    local d
                    d=$(get_duration_seconds "break")
                    build_output "󰅶" "$(format_time "$r")" "break" "$r" "$d"
                fi
            else
                check_tick "$remaining"
                local d
                d=$(get_duration_seconds "work")
                build_output "󱎫" "$(format_time "$remaining")" "work" "$remaining" "$d"
            fi
            ;;
        break)
            local remaining
            remaining=$(compute_remaining "break")
            if [ "$remaining" -le 0 ]; then
                handle_completion "break"
                local new_status
                new_status=$(read_state "status" "idle")
                if [ "$new_status" = "work" ]; then
                    local r
                    r=$(compute_remaining "work")
                    local d
                    d=$(get_duration_seconds "work")
                    build_output "󱎫" "$(format_time "$r")" "work" "$r" "$d"
                fi
            else
                check_tick "$remaining"
                local d
                d=$(get_duration_seconds "break")
                build_output "󰅶" "$(format_time "$remaining")" "break" "$remaining" "$d"
            fi
            ;;
    esac
}

main
