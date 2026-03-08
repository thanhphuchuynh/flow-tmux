#!/usr/bin/env bash
# groups.sh — Window group management (tag, filter, switch)
# Groups stored as window option @flow_group per window

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# ── Get/set group for a window ──
get_window_group() {
    local window="${1:-}"
    if [ -n "$window" ]; then
        tmux show-window-option -t "$window" -v "@flow_group" 2>/dev/null
    else
        tmux show-window-option -v "@flow_group" 2>/dev/null
    fi
}

set_window_group() {
    local group="$1"
    local window="${2:-}"
    if [ -n "$window" ]; then
        tmux set-window-option -t "$window" "@flow_group" "$group"
    else
        tmux set-window-option "@flow_group" "$group"
    fi
}

# ── Tag current window ──
tag_window() {
    local group="$1"
    if [ -z "$group" ]; then
        flow_message "group" "󰅖 Group name cannot be empty"
        return 1
    fi
    set_window_group "$group"
    local win_name
    win_name=$(tmux display-message -p '#W')
    flow_message "group" "󰓩 Window '$win_name' tagged as [$group]"
}

# ── Remove tag from current window ──
untag_window() {
    tmux set-window-option -u "@flow_group" 2>/dev/null
    flow_message "group" "󰓩 Window untagged"
}

# ── List all groups ──
list_groups() {
    local -a groups=()
    local windows
    windows=$(tmux list-windows -F '#{window_id}')
    for wid in $windows; do
        local g
        g=$(tmux show-window-option -t "$wid" -v "@flow_group" 2>/dev/null)
        if [ -n "$g" ]; then
            # Add to array if not already present
            local found=0
            for existing in "${groups[@]}"; do
                [ "$existing" = "$g" ] && found=1 && break
            done
            [ "$found" -eq 0 ] && groups+=("$g")
        fi
    done
    printf '%s\n' "${groups[@]}"
}

# ── Show only windows in a group (hide others) ──
focus_group() {
    local target_group="$1"
    if [ -z "$target_group" ]; then
        # Show all — clear filter
        _show_all_windows
        write_state "active_group" ""
        flow_message "group" "󰓩 Showing all windows"
        return
    fi

    write_state "active_group" "$target_group"

    # Find windows in group and not in group
    local first_in_group=""
    local windows
    windows=$(tmux list-windows -F '#{window_id} #{window_index}')
    while read -r wid widx; do
        local g
        g=$(tmux show-window-option -t "$wid" -v "@flow_group" 2>/dev/null)
        if [ "$g" = "$target_group" ]; then
            [ -z "$first_in_group" ] && first_in_group="$widx"
        fi
    done <<< "$windows"

    # Switch to first window in the group
    if [ -n "$first_in_group" ]; then
        tmux select-window -t "$first_in_group"
    fi

    flow_message "group" "󰓩 Focus: [$target_group]"
}

_show_all_windows() {
    write_state "active_group" ""
}

# ── Navigate within group (next/prev) ──
next_in_group() {
    local active_group
    active_group=$(read_state "active_group" "")
    [ -z "$active_group" ] && { tmux next-window; return; }

    local current_idx
    current_idx=$(tmux display-message -p '#{window_index}')
    local found_current=0
    local first_in_group=""

    local windows
    windows=$(tmux list-windows -F '#{window_id} #{window_index}' | sort -t' ' -k2 -n)
    while read -r wid widx; do
        local g
        g=$(tmux show-window-option -t "$wid" -v "@flow_group" 2>/dev/null)
        [ "$g" != "$active_group" ] && continue
        [ -z "$first_in_group" ] && first_in_group="$widx"
        if [ "$found_current" -eq 1 ]; then
            tmux select-window -t "$widx"
            return
        fi
        [ "$widx" = "$current_idx" ] && found_current=1
    done <<< "$windows"

    # Wrap around
    [ -n "$first_in_group" ] && tmux select-window -t "$first_in_group"
}

prev_in_group() {
    local active_group
    active_group=$(read_state "active_group" "")
    [ -z "$active_group" ] && { tmux previous-window; return; }

    local current_idx
    current_idx=$(tmux display-message -p '#{window_index}')
    local last_in_group=""
    local prev_wid=""

    local windows
    windows=$(tmux list-windows -F '#{window_id} #{window_index}' | sort -t' ' -k2 -n)
    while read -r wid widx; do
        local g
        g=$(tmux show-window-option -t "$wid" -v "@flow_group" 2>/dev/null)
        [ "$g" != "$active_group" ] && continue
        if [ "$widx" = "$current_idx" ] && [ -n "$prev_wid" ]; then
            tmux select-window -t "$prev_wid"
            return
        fi
        prev_wid="$widx"
        last_in_group="$widx"
    done <<< "$windows"

    # Wrap around
    [ -n "$last_in_group" ] && tmux select-window -t "$last_in_group"
}

# ── Show group picker menu ──
show_group_menu() {
    local groups_cmd="$CURRENT_DIR/groups.sh"
    local menu_items=()

    menu_items+=("󰓩 Tag Window"      "t" "run-shell '$groups_cmd _prompt_tag'")
    menu_items+=("󰓩 Untag Window"    "u" "run-shell '$groups_cmd untag'")
    menu_items+=(""                    ""  "")
    menu_items+=("󰋜 Show All"        "a" "run-shell '$groups_cmd focus'")
    menu_items+=(""                    ""  "")

    # List existing groups
    local groups
    groups=$(list_groups)
    local active_group
    active_group=$(read_state "active_group" "")
    if [ -n "$groups" ]; then
        while read -r g; do
            [ -z "$g" ] && continue
            local count=0
            local windows
            windows=$(tmux list-windows -F '#{window_id}')
            for wid in $windows; do
                local wg
                wg=$(tmux show-window-option -t "$wid" -v "@flow_group" 2>/dev/null)
                [ "$wg" = "$g" ] && count=$(( count + 1 ))
            done
            local label="$g ($count)"
            [ "$g" = "$active_group" ] && label="* $label"
            menu_items+=("$label" "" "run-shell '$groups_cmd focus $g'")
        done <<< "$groups"
    else
        menu_items+=("(no groups yet)" "" "")
    fi

    tmux display-menu -T " 󰓩 Window Groups " "${menu_items[@]}"
}

# ── Show group status for status bar ──
show_group_status() {
    local active_group
    active_group=$(read_state "active_group" "")
    [ -z "$active_group" ] && return

    local current_group
    current_group=$(get_window_group)
    if [ -n "$current_group" ]; then
        echo "[$current_group]"
    fi
}

# ── Prompt helpers ──
_prompt_tag() {
    local existing
    existing=$(list_groups | tr '\n' '/' | sed 's/\/$//')
    local hint="󰓩 Group name"
    [ -n "$existing" ] && hint="$hint ($existing)"
    tmux command-prompt -p "$hint:" \
        "run-shell \"$CURRENT_DIR/groups.sh tag '%1'\""
}

# ── Command dispatcher ──
case "${1:-}" in
    tag)         tag_window "${2:-}" ;;
    untag)       untag_window ;;
    focus)       focus_group "${2:-}" ;;
    next)        next_in_group ;;
    prev)        prev_in_group ;;
    list)        list_groups ;;
    menu)        show_group_menu ;;
    status)      show_group_status ;;
    _prompt_tag) _prompt_tag ;;
    *)
        echo "Usage: groups.sh {tag <name>|untag|focus [group]|next|prev|list|menu|status}"
        exit 1
        ;;
esac
