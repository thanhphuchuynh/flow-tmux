#!/usr/bin/env bash
# flow-tmux.tmux — TPM entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

source "$SCRIPTS_DIR/helpers.sh"

ensure_state_dir

if [ ! -f "$FLOW_STATE_DIR/status" ]; then
    write_state "status" "idle"
    write_state "session_count" "0"
fi

setup_flow_status() {
    local status_cmd="#($SCRIPTS_DIR/status.sh)"
    local status_right
    status_right=$(tmux show-option -gqv "status-right")
    if [[ "$status_right" == *'#{flow_status}'* ]]; then
        status_right="${status_right//'#{flow_status}'/$status_cmd}"
        tmux set-option -gq "status-right" "$status_right"
    fi
    local status_left
    status_left=$(tmux show-option -gqv "status-left")
    if [[ "$status_left" == *'#{flow_status}'* ]]; then
        status_left="${status_left//'#{flow_status}'/$status_cmd}"
        tmux set-option -gq "status-left" "$status_left"
    fi
}

setup_keybindings() {
    local toggle_key cancel_key menu_key tasks_key
    toggle_key=$(get_tmux_option "@flow_toggle_key" "F")
    cancel_key=$(get_tmux_option "@flow_cancel_key" "C-f")
    menu_key=$(get_tmux_option "@flow_menu_key" "M-f")
    tasks_key=$(get_tmux_option "@flow_tasks_key" "T")

    local dashboard_key
    dashboard_key=$(get_tmux_option "@flow_dashboard_key" "C-l")

    tmux bind-key "$toggle_key" run-shell "$SCRIPTS_DIR/flow.sh toggle"
    tmux bind-key "$cancel_key" run-shell "$SCRIPTS_DIR/flow.sh cancel"
    tmux bind-key "$menu_key" run-shell "$SCRIPTS_DIR/menu.sh"
    tmux bind-key "$tasks_key" run-shell "$SCRIPTS_DIR/tasks.sh menu"
    tmux bind-key "$dashboard_key" run-shell "$SCRIPTS_DIR/dashboard.sh toggle"

    # Distraction log hotkey (if enabled)
    if [ "$(get_distraction_enabled)" = "on" ]; then
        local distraction_key
        distraction_key=$(get_tmux_option "@flow_distraction_key" "D")
        tmux bind-key "$distraction_key" run-shell "$SCRIPTS_DIR/distraction.sh prompt"
    fi

    # Window groups
    local groups_key
    groups_key=$(get_tmux_option "@flow_groups_key" "G")
    tmux bind-key "$groups_key" run-shell "$SCRIPTS_DIR/groups.sh menu"
    # Navigate within group: prefix + Ctrl+n / Ctrl+p
    tmux bind-key C-n run-shell "$SCRIPTS_DIR/groups.sh next"
    tmux bind-key C-p run-shell "$SCRIPTS_DIR/groups.sh prev"

    # Window picker: w = current session only, W = all sessions
    tmux bind-key w run-shell "$SCRIPTS_DIR/winpicker.sh"
    tmux bind-key W choose-tree -Z

    # Projects (if enabled)
    if [ "$(get_projects_enabled)" = "on" ]; then
        local projects_key
        projects_key=$(get_tmux_option "@flow_projects_key" "P")
        tmux bind-key "$projects_key" run-shell "$SCRIPTS_DIR/projects.sh menu"
    fi

    # Notifications (if enabled)
    if [ "$(get_notifications_enabled)" = "on" ]; then
        local notifications_key
        notifications_key=$(get_tmux_option "@flow_notifications_key" "N")
        tmux bind-key "$notifications_key" run-shell "$SCRIPTS_DIR/notifications.sh show"
    fi
}

setup_window_group_format() {
    # Show group tag in window status format: "1:vim [api]"
    local current_fmt
    current_fmt=$(tmux show-option -gqv "window-status-format")
    # Only add if not already present
    if [[ "$current_fmt" != *"flow_group"* ]]; then
        tmux set-option -gq "window-status-format" \
            "$current_fmt#{?#{@flow_group}, [#{@flow_group}],}"
        local current_active
        current_active=$(tmux show-option -gqv "window-status-current-format")
        tmux set-option -gq "window-status-current-format" \
            "$current_active#{?#{@flow_group}, [#{@flow_group}],}"
    fi
}

setup_flow_status
setup_keybindings
setup_window_group_format
