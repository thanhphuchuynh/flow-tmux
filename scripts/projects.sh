#!/usr/bin/env bash
# projects.sh — Project launcher (list, open, menu, edit)
# Config: ~/.cache/flow-tmux/projects.conf
# Format:
#   project:<name>
#   window:<win_name>|<dir>|<command>

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# ── Parse projects.conf ──
list_projects() {
    [ -f "$FLOW_PROJECTS_FILE" ] || return
    grep '^project:' "$FLOW_PROJECTS_FILE" | sed 's/^project://'
}

# Get windows for a project (outputs: name|dir|cmd per line)
get_project_windows() {
    local name="$1"
    [ -f "$FLOW_PROJECTS_FILE" ] || return
    local in_project=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == "#"* ]] && continue
        if [[ "$line" == "project:"* ]]; then
            local pname="${line#project:}"
            if [ "$pname" = "$name" ]; then
                in_project=1
            else
                [ "$in_project" -eq 1 ] && break
            fi
        elif [ "$in_project" -eq 1 ] && [[ "$line" == "window:"* ]]; then
            echo "${line#window:}"
        fi
    done < "$FLOW_PROJECTS_FILE"
}

# ── Open a project ──
open_project() {
    local name="$1"
    [ -z "$name" ] && { flow_message "project" "󰅖 Project name required"; return 1; }

    local windows
    windows=$(get_project_windows "$name")
    [ -z "$windows" ] && { flow_message "project" "󰅖 Project '$name' not found"; return 1; }

    local first_window=1
    while IFS='|' read -r win_name win_dir win_cmd; do
        [ -z "$win_name" ] && continue
        # Expand ~ in directory
        win_dir="${win_dir/#\~/$HOME}"
        if [ "$first_window" -eq 1 ]; then
            # Create first window (rename current or new)
            tmux new-window -n "$win_name" -c "$win_dir"
            first_window=0
        else
            tmux new-window -n "$win_name" -c "$win_dir"
        fi
        # Tag window with project group
        tmux set-window-option "@flow_group" "$name"
        # Run command if provided
        [ -n "$win_cmd" ] && tmux send-keys "$win_cmd" Enter
    done <<< "$windows"

    write_state "active_group" "$name"
    flow_message "project" "󰝰 Project '$name' opened"
}

# ── Show project picker menu ──
show_menu() {
    local projects
    projects=$(list_projects)
    [ -z "$projects" ] && { flow_message "project" "No projects configured. Use 'prefix+P' → Edit to create one."; return; }

    local projects_cmd="$CURRENT_DIR/projects.sh"
    local menu_items=()

    while read -r name; do
        [ -z "$name" ] && continue
        menu_items+=("$name" "" "run-shell '$projects_cmd open $name'")
    done <<< "$projects"

    menu_items+=(""     ""  "")
    menu_items+=("Edit" "e" "run-shell '$projects_cmd edit'")

    tmux display-menu -T " 󰝰 Projects " "${menu_items[@]}"
}

# ── Edit projects.conf ──
edit_projects() {
    ensure_stats_dir
    [ -f "$FLOW_PROJECTS_FILE" ] || cat > "$FLOW_PROJECTS_FILE" << 'EOF'
# flow-tmux projects — one project per block
# Format:
#   project:<name>
#   window:<window_name>|<directory>|<command>
#
# Example:
# project:my-app
# window:editor|~/code/my-app|nvim .
# window:server|~/code/my-app|npm run dev
# window:logs|~/code/my-app|tail -f logs/app.log
EOF
    local editor="${EDITOR:-vim}"
    tmux display-popup -w 70 -h 24 -T " 󰝰 Edit Projects " \
        -E "$editor '$FLOW_PROJECTS_FILE'"
}

# ── Prompt for project name ──
_prompt_open() {
    local projects
    projects=$(list_projects)
    if [ -z "$projects" ]; then
        flow_message "project" "No projects configured. Run edit first."
        return
    fi
    show_menu
}

case "${1:-}" in
    list)         list_projects ;;
    open)         open_project "${2:-}" ;;
    menu)         show_menu ;;
    edit)         edit_projects ;;
    _prompt_open) _prompt_open ;;
    *)            echo "Usage: projects.sh {list|open <name>|menu|edit}"; exit 1 ;;
esac
