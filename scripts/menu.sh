#!/usr/bin/env bash
# menu.sh — Interactive popup menu via tmux display-menu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

show_menu() {
    local status
    status=$(read_state "status" "idle")
    local flow_cmd="$CURRENT_DIR/flow.sh"
    local stats_cmd="$CURRENT_DIR/stats.sh"
    local tasks_cmd="$CURRENT_DIR/tasks.sh"
    local distraction_cmd="$CURRENT_DIR/distraction.sh"

    local pause_label pause_action
    if [ "$status" = "paused" ]; then
        pause_label="Resume"
        pause_action="run-shell '$flow_cmd resume'"
    else
        pause_label="Pause"
        pause_action="run-shell '$flow_cmd pause'"
    fi

    local menu_items=()

    # Timer controls
    menu_items+=("Start Work"      "w" "run-shell '$flow_cmd start_work'")
    menu_items+=("Start with Goal" "g" "run-shell '$flow_cmd start_work_with_goal'")
    menu_items+=("Start Break"     "b" "run-shell '$flow_cmd start_break'")
    menu_items+=(""                ""  "")
    menu_items+=("$pause_label"    "p" "$pause_action")
    menu_items+=("Skip to Next"    "s" "run-shell '$flow_cmd skip'")
    menu_items+=("Cancel"          "c" "run-shell '$flow_cmd cancel'")
    menu_items+=(""                ""  "")

    # Task shortcuts
    menu_items+=("󰐃 Tasks"         "t" "run-shell '$tasks_cmd menu'")
    menu_items+=("󰀘 Pick & Focus"  "f" "run-shell '$tasks_cmd pick'")
    menu_items+=("󰄬 Complete Task" "d" "run-shell '$tasks_cmd complete'")
    menu_items+=(""                ""  "")

    # Distraction log (if enabled)
    if [ "$(get_distraction_enabled)" = "on" ]; then
        menu_items+=("󰍉 Log Distraction" "D" "run-shell '$distraction_cmd prompt'")
        menu_items+=("󰍉 View Distractions" "V" "run-shell '$distraction_cmd show'")
        menu_items+=(""                ""  "")
    fi

    # Stats
    menu_items+=("View Stats"      "v" "run-shell '$stats_cmd show'")
    if [ "$(get_weekly_report_enabled)" = "on" ]; then
        menu_items+=("󰄧 Weekly Report" "W" "run-shell '$stats_cmd weekly'")
    fi
    if [ "$(get_heatmap_enabled)" = "on" ]; then
        menu_items+=("󰄧 Heatmap"       "H" "run-shell '$stats_cmd heatmap'")
    fi
    if [ "$(get_export_enabled)" = "on" ]; then
        menu_items+=("󰄧 Export JSON"    "J" "run-shell '$stats_cmd export json'")
        menu_items+=("󰄧 Export MD"      "M" "run-shell '$stats_cmd export md'")
    fi

    # Window groups
    local groups_cmd="$CURRENT_DIR/groups.sh"
    menu_items+=(""                    ""  "")
    menu_items+=("󰓩 Window Groups"    "G" "run-shell '$groups_cmd menu'")

    # Projects (if enabled)
    if [ "$(get_projects_enabled)" = "on" ]; then
        local projects_cmd="$CURRENT_DIR/projects.sh"
        menu_items+=(""                    ""  "")
        menu_items+=("󰝰 Projects"         "P" "run-shell '$projects_cmd menu'")
    fi

    # Notifications (if enabled)
    if [ "$(get_notifications_enabled)" = "on" ]; then
        local notif_cmd="$CURRENT_DIR/notifications.sh"
        local unread
        unread=$("$notif_cmd" count)
        local notif_label="󰂚 Notifications"
        [ "$unread" -gt 0 ] && notif_label="󰂚 Notifications ($unread)"
        menu_items+=(""                    ""  "")
        menu_items+=("$notif_label"        "N" "run-shell '$notif_cmd show'")
        menu_items+=("󰂚 Clear All"        "X" "run-shell '$notif_cmd clear'")
    fi

    # System monitor
    local sysmon_cmd="$CURRENT_DIR/sysmon.sh"
    menu_items+=(""                    ""  "")
    menu_items+=(" System Monitor"    "S" "run-shell '$sysmon_cmd menu'")

    # Dashboard
    local dash_cmd="$CURRENT_DIR/dashboard.sh"
    menu_items+=(""                    ""  "")
    menu_items+=("󰖟 Toggle Dashboard" "L" "run-shell '$dash_cmd toggle'")

    tmux display-menu -T "󱎫 Flow Timer" "${menu_items[@]}"
}

show_menu
