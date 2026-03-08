#!/usr/bin/env bash
# tasks.sh — Kanban task management with priority, tracking, subtasks, recurring
# TSV format: id\tstatus\ttitle\tcreated\tpriority\tpomodoros\trecurring

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

TASKS_FILE="$FLOW_TASKS_FILE"

ensure_tasks_file() {
    ensure_stats_dir
    touch "$TASKS_FILE"
}

# Read a task field. Handles old 4-col and new 7-col format gracefully.
parse_task() {
    local line="$1"
    T_ID="" T_STATUS="" T_TITLE="" T_CREATED="" T_PRIORITY="-" T_POMODOROS="0" T_RECURRING=""
    IFS=$'\t' read -r T_ID T_STATUS T_TITLE T_CREATED T_PRIORITY T_POMODOROS T_RECURRING <<< "$line"
    [ -z "$T_PRIORITY" ] && T_PRIORITY="-"
    [ -z "$T_POMODOROS" ] && T_POMODOROS="0"
    [ -z "$T_RECURRING" ] && T_RECURRING=""
}

format_task_line() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$T_ID" "$T_STATUS" "$T_TITLE" "$T_CREATED" "$T_PRIORITY" "$T_POMODOROS" "$T_RECURRING"
}

next_id() {
    ensure_tasks_file
    local max=0
    while IFS=$'\t' read -r id _; do
        [ "$id" -gt "$max" ] 2>/dev/null && max="$id"
    done < "$TASKS_FILE"
    echo $(( max + 1 ))
}

# ── Priority helpers ──
priority_symbol() {
    case "$1" in
        "!") echo "!" ;;
        "~") echo "~" ;;
        *)   echo "-" ;;
    esac
}

priority_sort_key() {
    case "$1" in
        "!") echo "1" ;;
        "-") echo "2" ;;
        "~") echo "3" ;;
        *)   echo "2" ;;
    esac
}

# ── Core operations ──
add_task() {
    local title="$1"
    [ -z "$title" ] && { flow_message "task" "󰅖 Task title cannot be empty"; return 1; }
    ensure_tasks_file
    local id
    id=$(next_id)
    local priority="-"
    local recurring=""
    # Parse priority prefix: !task or ~task
    if [[ "$title" == "!"* ]]; then
        priority="!"
        title="${title#!}"
        title="${title# }"
    elif [[ "$title" == "~"* ]]; then
        priority="~"
        title="${title#\~}"
        title="${title# }"
    fi
    # Parse recurring suffix: task @daily
    if [[ "$title" == *" @daily" ]]; then
        recurring="daily"
        title="${title% @daily}"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "todo" "$title" "$(date +%Y-%m-%dT%H:%M:%S)" "$priority" "0" "$recurring" >> "$TASKS_FILE"
    local extra=""
    [ "$priority" = "!" ] && extra=" [HIGH]"
    [ "$recurring" = "daily" ] && extra="$extra [recurring]"
    flow_message "task" "󰄬 Task #$id added: $title$extra"
}

set_task_status() {
    local target_id="$1" new_status="$2"
    ensure_tasks_file
    local tmpfile found=0
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        parse_task "$line"
        if [ "$T_ID" = "$target_id" ]; then
            T_STATUS="$new_status"
            found=1
        fi
        format_task_line >> "$tmpfile"
    done < "$TASKS_FILE"
    mv "$tmpfile" "$TASKS_FILE"
    [ "$found" -eq 0 ] && flow_message "task" "󰅖 Task #$target_id not found"
}

focus_task() {
    local target_id="$1"
    ensure_tasks_file
    local task_title="" task_found=0
    while IFS= read -r line; do
        parse_task "$line"
        if [ "$T_ID" = "$target_id" ]; then
            task_title="$T_TITLE"
            task_found=1
            break
        fi
    done < "$TASKS_FILE"
    [ "$task_found" -eq 0 ] && { flow_message "task" "󰅖 Task #$target_id not found"; return 1; }

    # Move other in_progress tasks back to todo
    local tmpfile
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        parse_task "$line"
        if [ "$T_STATUS" = "in_progress" ] && [ "$T_ID" != "$target_id" ]; then
            T_STATUS="todo"
        fi
        format_task_line >> "$tmpfile"
    done < "$TASKS_FILE"
    mv "$tmpfile" "$TASKS_FILE"

    set_task_status "$target_id" "in_progress"
    write_state "current_task_id" "$target_id"
    write_state "goal" "$task_title"
    "$CURRENT_DIR/flow.sh" start_work
}

complete_current_task() {
    local task_id
    task_id=$(read_state "current_task_id" "")
    if [ -n "$task_id" ]; then
        set_task_status "$task_id" "done"
        rm -f "$FLOW_STATE_DIR/current_task_id"
        flow_message "task" "󰄬 Task #$task_id marked done!"
    else
        flow_message "task" "No active task"
    fi
}

delete_task() {
    local target_id="$1"
    ensure_tasks_file
    local tmpfile found=0
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        parse_task "$line"
        if [ "$T_ID" = "$target_id" ]; then
            found=1
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$TASKS_FILE"
    mv "$tmpfile" "$TASKS_FILE"
    # Also delete subtasks
    if [ -f "$FLOW_SUBTASKS_FILE" ]; then
        local stmp
        stmp=$(mktemp)
        grep -v "^${target_id}	" "$FLOW_SUBTASKS_FILE" > "$stmp" 2>/dev/null || true
        mv "$stmp" "$FLOW_SUBTASKS_FILE"
    fi
    [ "$found" -eq 1 ] && flow_message "task" "󰆴 Task #$target_id deleted" || flow_message "task" "󰅖 Task #$target_id not found"
}

# ── Pomodoro tracking ──
_inc_pomodoro() {
    local target_id="$1"
    ensure_tasks_file
    local tmpfile
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        parse_task "$line"
        if [ "$T_ID" = "$target_id" ]; then
            T_POMODOROS=$(( T_POMODOROS + 1 ))
        fi
        format_task_line >> "$tmpfile"
    done < "$TASKS_FILE"
    mv "$tmpfile" "$TASKS_FILE"
}

# ── Subtasks ──
add_subtask() {
    local parent_id="$1" title="$2"
    [ -z "$title" ] && { flow_message "task" "󰅖 Subtask title cannot be empty"; return 1; }
    ensure_stats_dir
    touch "$FLOW_SUBTASKS_FILE"
    # Find next subtask index for this parent
    local max=0
    while IFS=$'\t' read -r pid sid _ _; do
        if [ "$pid" = "$parent_id" ] && [ "$sid" -gt "$max" ] 2>/dev/null; then
            max="$sid"
        fi
    done < "$FLOW_SUBTASKS_FILE"
    local sid=$(( max + 1 ))
    printf '%s\t%s\t%s\t%s\n' "$parent_id" "$sid" "todo" "$title" >> "$FLOW_SUBTASKS_FILE"
    flow_message "task" "󰄬 Subtask #$parent_id.$sid added: $title"
}

complete_subtask() {
    local parent_id="$1" sub_id="$2"
    [ -f "$FLOW_SUBTASKS_FILE" ] || { flow_message "task" "No subtasks"; return; }
    local tmpfile found=0
    tmpfile=$(mktemp)
    while IFS=$'\t' read -r pid sid status title; do
        if [ "$pid" = "$parent_id" ] && [ "$sid" = "$sub_id" ]; then
            printf '%s\t%s\t%s\t%s\n' "$pid" "$sid" "done" "$title" >> "$tmpfile"
            found=1
        else
            printf '%s\t%s\t%s\t%s\n' "$pid" "$sid" "$status" "$title" >> "$tmpfile"
        fi
    done < "$FLOW_SUBTASKS_FILE"
    mv "$tmpfile" "$FLOW_SUBTASKS_FILE"
    [ "$found" -eq 1 ] && flow_message "task" "󰄬 Subtask #$parent_id.$sub_id done!" || flow_message "task" "󰅖 Subtask not found"
}

# ── Board display ──
show_board() {
    ensure_tasks_file
    local in_progress="" todos="" dones=""
    local show_priority
    show_priority=$(get_priority_enabled)
    local show_tracking
    show_tracking=$(get_tracking_enabled)

    # Collect tasks with sort keys
    local -a sorted_lines=()
    while IFS= read -r line; do
        parse_task "$line"
        local prefix=""
        [ "$show_priority" = "on" ] && prefix="$(priority_symbol "$T_PRIORITY") "
        local suffix=""
        [ "$show_tracking" = "on" ] && [ "$T_POMODOROS" -gt 0 ] && suffix=" [${T_POMODOROS}x]"
        local recurring_tag=""
        [ -n "$T_RECURRING" ] && recurring_tag=" 󰑖"
        local display="  ${prefix}#${T_ID} ${T_TITLE}${suffix}${recurring_tag}"

        # Collect subtasks
        local subtask_lines=""
        if [ "$(get_subtasks_enabled)" = "on" ] && [ -f "$FLOW_SUBTASKS_FILE" ]; then
            while IFS=$'\t' read -r pid sid sstatus stitle; do
                if [ "$pid" = "$T_ID" ]; then
                    local check="  "
                    [ "$sstatus" = "done" ] && check="󰄬 "
                    subtask_lines+="    ${check}${stitle}\n"
                fi
            done < "$FLOW_SUBTASKS_FILE"
        fi

        local sort_key
        sort_key=$(priority_sort_key "$T_PRIORITY")
        case "$T_STATUS" in
            in_progress) in_progress+="${display}\n${subtask_lines}" ;;
            todo)        todos+="${sort_key}|${display}\n${subtask_lines}" ;;
            done)        dones+="${display}\n${subtask_lines}" ;;
        esac
    done < "$TASKS_FILE"

    # Sort todos by priority if enabled
    if [ "$show_priority" = "on" ] && [ -n "$todos" ]; then
        todos=$(echo -e "$todos" | sort -t'|' -k1,1 | sed 's/^[0-9]|//')
    else
        todos=$(echo -e "$todos" | sed 's/^[0-9]|//')
    fi

    [ -z "$in_progress" ] && in_progress="  (none)\n"
    [ -z "$todos" ] && todos="  (none)\n"
    [ -z "$dones" ] && dones="  (none)\n"

    local board=""
    board+="━━━ 󰈸 IN PROGRESS ━━━\n"
    board+="$in_progress"
    board+="\n━━━ 󰃨 TODO ━━━\n"
    board+="$todos"
    board+="\n━━━ 󰄬 DONE ━━━\n"
    board+="$dones"

    tmux display-popup -w 55 -h 24 -T " 󰐃 Task Board " \
        -E "printf '$board' | less -R"
}

show_pick_menu() {
    ensure_tasks_file
    local tasks_cmd="$CURRENT_DIR/tasks.sh"
    local menu_args=()
    local has_tasks=0
    local show_priority
    show_priority=$(get_priority_enabled)

    while IFS= read -r line; do
        parse_task "$line"
        if [ "$T_STATUS" = "todo" ]; then
            local display_title="$T_TITLE"
            [ ${#display_title} -gt 28 ] && display_title="${display_title:0:26}.."
            local prefix=""
            [ "$show_priority" = "on" ] && prefix="$(priority_symbol "$T_PRIORITY") "
            menu_args+=("${prefix}#${T_ID} ${display_title}" "" "run-shell '$tasks_cmd focus $T_ID'")
            has_tasks=1
        fi
    done < "$TASKS_FILE"

    [ "$has_tasks" -eq 0 ] && { flow_message "task" "󰃨 No todo tasks. Add one first!"; return; }
    tmux display-menu -T " 󰀘 Pick a Task " "${menu_args[@]}"
}

show_task_menu() {
    local tasks_cmd="$CURRENT_DIR/tasks.sh"
    local menu_items=()

    menu_items+=("󰃨 View Board"       "b" "run-shell '$tasks_cmd board'")
    menu_items+=("󰐕 Add Task"          "a" "run-shell '$tasks_cmd _prompt_add'")
    menu_items+=("󰀘 Pick & Focus"     "f" "run-shell '$tasks_cmd pick'")
    menu_items+=(""                     ""  "")
    menu_items+=("󰄬 Complete Current"  "d" "run-shell '$tasks_cmd complete'")
    menu_items+=("󰆴 Delete Task"      "x" "run-shell '$tasks_cmd _prompt_delete'")

    if [ "$(get_subtasks_enabled)" = "on" ]; then
        menu_items+=(""                     ""  "")
        menu_items+=("󰐕 Add Subtask"       "s" "run-shell '$tasks_cmd _prompt_subtask'")
        menu_items+=("󰄬 Complete Subtask"  "S" "run-shell '$tasks_cmd _prompt_complete_subtask'")
    fi

    tmux display-menu -T " 󰐃 Tasks " "${menu_items[@]}"
}

_prompt_add() {
    local hint="󰐕 New task"
    [ "$(get_priority_enabled)" = "on" ] && hint="$hint (!high ~low)"
    [ "$(get_recurring_enabled)" = "on" ] && hint="$hint (@daily)"
    tmux command-prompt -p "$hint:" \
        "run-shell \"$CURRENT_DIR/tasks.sh add '%1'\""
}

_prompt_delete() {
    tmux command-prompt -p "󰆴 Delete task #:" \
        "run-shell \"$CURRENT_DIR/tasks.sh delete '%1'\""
}

_prompt_subtask() {
    tmux command-prompt -p "Parent task #:" -p "Subtask title:" \
        "run-shell \"$CURRENT_DIR/tasks.sh add_subtask '%1' '%2'\""
}

_prompt_complete_subtask() {
    tmux command-prompt -p "Task #:" -p "Subtask #:" \
        "run-shell \"$CURRENT_DIR/tasks.sh complete_subtask '%1' '%2'\""
}

case "${1:-}" in
    add)                   add_task "${2:-}" ;;
    focus)                 focus_task "${2:-}" ;;
    complete)              complete_current_task ;;
    delete)                delete_task "${2:-}" ;;
    board)                 show_board ;;
    pick)                  show_pick_menu ;;
    menu)                  show_task_menu ;;
    add_subtask)           add_subtask "${2:-}" "${3:-}" ;;
    complete_subtask)      complete_subtask "${2:-}" "${3:-}" ;;
    _inc_pomodoro)         _inc_pomodoro "${2:-}" ;;
    _prompt_add)           _prompt_add ;;
    _prompt_delete)        _prompt_delete ;;
    _prompt_subtask)       _prompt_subtask ;;
    _prompt_complete_subtask) _prompt_complete_subtask ;;
    *)
        echo "Usage: tasks.sh {add|focus|complete|delete|board|pick|menu|add_subtask|complete_subtask}"
        exit 1
        ;;
esac
