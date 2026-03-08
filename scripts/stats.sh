#!/usr/bin/env bash
# stats.sh — Session statistics, weekly report, export, heatmap

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

log_session() {
    local type="$1"
    local duration
    if [ "$type" = "work" ]; then
        duration=$(get_work_duration)
    else
        local session_count
        session_count=$(read_state "session_count" "0")
        local long_break_after
        long_break_after=$(get_long_break_after)
        if [ "$session_count" -gt 0 ] && [ $((session_count % long_break_after)) -eq 0 ]; then
            duration=$(get_long_break_duration)
        else
            duration=$(get_break_duration)
        fi
    fi
    local goal
    goal=$(read_state "goal" "")
    ensure_stats_dir
    echo "$(date +%Y-%m-%dT%H:%M:%S),$duration,$type,$goal" >> "$FLOW_STATS_FILE"
}

show_stats() {
    [ -f "$FLOW_STATS_FILE" ] || { flow_message "info" "󰄧 No sessions recorded yet"; return; }
    local today
    today=$(date +%Y-%m-%d)
    local today_work=0 today_minutes=0 total_work=0 total_minutes=0
    while IFS=',' read -r timestamp duration type _; do
        if [ "$type" = "work" ]; then
            total_work=$(( total_work + 1 ))
            total_minutes=$(( total_minutes + duration ))
            [[ "$timestamp" == "$today"* ]] && {
                today_work=$(( today_work + 1 ))
                today_minutes=$(( today_minutes + duration ))
            }
        fi
    done < "$FLOW_STATS_FILE"
    local msg="󰄧 Today: ${today_work} sessions ($(( today_minutes / 60 ))h$(( today_minutes % 60 ))m)"
    msg+=" | Total: ${total_work} sessions ($(( total_minutes / 60 ))h$(( total_minutes % 60 ))m)"
    # Append streak if enabled
    if [ "$(get_streak_enabled)" = "on" ]; then
        local streak
        streak=$(calculate_streak)
        msg+=" | 󰈸 ${streak}d streak"
    fi
    flow_message "info" "$msg"
}

# ── Weekly Report ──
weekly_report() {
    [ -f "$FLOW_STATS_FILE" ] || { flow_message "info" "󰄧 No sessions recorded yet"; return; }

    local content="━━━ 󰄧 Weekly Report ━━━\n\n"

    # Collect last 7 days
    for i in $(seq 0 6); do
        local day
        if date -v-${i}d +%Y-%m-%d &>/dev/null 2>&1; then
            day=$(date -v-${i}d +%Y-%m-%d)
        else
            day=$(date -d "today - $i days" +%Y-%m-%d)
        fi
        local day_name
        if date -v-${i}d +%a &>/dev/null 2>&1; then
            day_name=$(date -j -f "%Y-%m-%d" "$day" +%a 2>/dev/null || echo "???")
        else
            day_name=$(date -d "$day" +%a 2>/dev/null || echo "???")
        fi
        local count=0 minutes=0
        while IFS=',' read -r timestamp duration type _; do
            if [ "$type" = "work" ] && [[ "$timestamp" == "$day"* ]]; then
                count=$(( count + 1 ))
                minutes=$(( minutes + duration ))
            fi
        done < "$FLOW_STATS_FILE"
        local bar=""
        for ((j=0; j<count && j<12; j++)); do bar+="█"; done
        local pad=$(( 12 - ${#bar} ))
        for ((j=0; j<pad; j++)); do bar+="░"; done
        content+="  $day_name $day  $bar  ${count} ($(( minutes / 60 ))h$(( minutes % 60 ))m)\n"
    done

    # Most productive hour
    local -a hours=()
    for ((h=0; h<24; h++)); do hours[$h]=0; done
    while IFS=',' read -r timestamp _ type _; do
        if [ "$type" = "work" ]; then
            local hour="${timestamp#*T}"
            hour="${hour%%:*}"
            hour=$((10#$hour))
            hours[$hour]=$(( ${hours[$hour]} + 1 ))
        fi
    done < "$FLOW_STATS_FILE"
    local max_h=0 max_count=0
    for ((h=0; h<24; h++)); do
        if [ "${hours[$h]}" -gt "$max_count" ]; then
            max_count="${hours[$h]}"
            max_h=$h
        fi
    done
    content+="\n  Most productive hour: $(printf '%02d' $max_h):00 ($max_count sessions)\n"

    # Streak
    if [ "$(get_streak_enabled)" = "on" ]; then
        local streak
        streak=$(calculate_streak)
        content+="  Current streak: 󰈸 ${streak} days\n"
    fi

    tmux display-popup -w 60 -h 18 -T " 󰄧 Weekly Report " \
        -E "printf '$content' | less -R"
}

# ── Heatmap ──
show_heatmap() {
    [ -f "$FLOW_STATS_FILE" ] || { flow_message "info" "󰄧 No sessions recorded yet"; return; }

    local content="━━━ 󰄧 Focus Heatmap (4 weeks) ━━━\n\n"
    content+="         Mon Tue Wed Thu Fri Sat Sun\n"

    # Build 4 weeks of data
    for week in $(seq 3 -1 0); do
        local week_label="W-$week"
        [ "$week" -eq 0 ] && week_label="This"
        content+="  $(printf '%-5s' "$week_label")"
        for dow in $(seq 1 7); do
            local days_ago=$(( week * 7 + (7 - dow) ))
            local day
            if date -v-${days_ago}d +%Y-%m-%d &>/dev/null 2>&1; then
                day=$(date -v-${days_ago}d +%Y-%m-%d)
            else
                day=$(date -d "today - $days_ago days" +%Y-%m-%d)
            fi
            local count=0
            while IFS=',' read -r timestamp _ type _; do
                [ "$type" = "work" ] && [[ "$timestamp" == "$day"* ]] && count=$(( count + 1 ))
            done < "$FLOW_STATS_FILE"
            local block=" ░ "
            [ "$count" -ge 1 ] && block=" ▒ "
            [ "$count" -ge 3 ] && block=" ▓ "
            [ "$count" -ge 6 ] && block=" █ "
            content+="$block"
        done
        content+="\n"
    done
    content+="\n  ░ = 0  ▒ = 1-2  ▓ = 3-5  █ = 6+\n"

    tmux display-popup -w 48 -h 14 -T " 󰄧 Heatmap " \
        -E "printf '$content' | less -R"
}

# ── Export ──
export_stats() {
    local format="${1:-json}"
    [ -f "$FLOW_STATS_FILE" ] || { flow_message "info" "󰄧 No sessions to export"; return; }
    ensure_stats_dir
    local outfile

    if [ "$format" = "json" ]; then
        outfile="$FLOW_STATS_DIR/export.json"
        echo "[" > "$outfile"
        local first=1
        while IFS=',' read -r timestamp duration type goal; do
            [ "$first" -eq 0 ] && echo "," >> "$outfile"
            printf '  {"timestamp":"%s","duration":%s,"type":"%s","goal":"%s"}' \
                "$timestamp" "$duration" "$type" "$goal" >> "$outfile"
            first=0
        done < "$FLOW_STATS_FILE"
        echo "" >> "$outfile"
        echo "]" >> "$outfile"
    else
        outfile="$FLOW_STATS_DIR/export.md"
        echo "# Flow Sessions" > "$outfile"
        echo "" >> "$outfile"
        echo "| Timestamp | Duration | Type | Goal |" >> "$outfile"
        echo "|-----------|----------|------|------|" >> "$outfile"
        while IFS=',' read -r timestamp duration type goal; do
            echo "| $timestamp | ${duration}m | $type | $goal |" >> "$outfile"
        done < "$FLOW_STATS_FILE"
    fi
    flow_message "info" "󰄧 Exported to $outfile"
}

case "${1:-}" in
    log)     log_session "${2:-work}" ;;
    show)    show_stats ;;
    weekly)  weekly_report ;;
    heatmap) show_heatmap ;;
    export)  export_stats "${2:-json}" ;;
    *)       echo "Usage: stats.sh {log|show|weekly|heatmap|export [json|md]}"; exit 1 ;;
esac
