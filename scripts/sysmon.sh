#!/usr/bin/env bash
# sysmon.sh — Show memory/CPU usage per tmux session or window

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

SYSMON_TMP="/tmp/flow_tmux_sysmon.txt"

# ── Colors ──
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"
C_RED="\033[31m"
C_BG_DIM="\033[48;5;236m"

# Get all descendant PIDs of a given PID
get_descendants() {
    local pid="$1"
    local children
    children=$(pgrep -P "$pid" 2>/dev/null)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Sum RSS (KB) and %CPU for a pane's process tree
pane_resources() {
    local pane_pid="$1"
    [ -z "$pane_pid" ] && { echo "0 0.0"; return; }
    local pids=("$pane_pid")
    while IFS= read -r p; do
        [ -n "$p" ] && pids+=("$p")
    done < <(get_descendants "$pane_pid")

    local total_rss=0 total_cpu="0.0"
    for pid in "${pids[@]}"; do
        local info
        info=$(ps -o rss=,pcpu= -p "$pid" 2>/dev/null) || continue
        local rss cpu
        read -r rss cpu <<< "$info"
        total_rss=$(( total_rss + rss ))
        total_cpu=$(awk "BEGIN{printf \"%.1f\", $total_cpu + $cpu}")
    done
    echo "$total_rss $total_cpu"
}

format_mem() {
    local kb="$1"
    if [ "$kb" -ge 1048576 ]; then
        awk "BEGIN{printf \"%.1fG\", $kb/1048576}"
    elif [ "$kb" -ge 1024 ]; then
        awk "BEGIN{printf \"%.1fM\", $kb/1024}"
    else
        echo "${kb}K"
    fi
}

# Memory bar: visualize usage relative to max in the list
mem_bar() {
    local kb="$1" max_kb="$2"
    local width=15
    [ "$max_kb" -le 0 ] && max_kb=1
    local filled=$(( kb * width / max_kb ))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 1 ] && [ "$kb" -gt 0 ] && filled=1
    local empty=$(( width - filled ))

    # Color based on percentage
    local pct=$(( kb * 100 / max_kb ))
    local color="$C_GREEN"
    [ "$pct" -ge 50 ] && color="$C_YELLOW"
    [ "$pct" -ge 80 ] && color="$C_RED"

    local bar="${color}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    bar+="${C_DIM}"
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="${C_RESET}"
    echo -e "$bar"
}

# CPU indicator
cpu_indicator() {
    local cpu="$1"
    local val=${cpu%.*}
    local color="$C_GREEN"
    [ "$val" -ge 30 ] && color="$C_YELLOW"
    [ "$val" -ge 70 ] && color="$C_RED"
    echo -e "${color}${cpu}%${C_RESET}"
}

# Horizontal line
hr() {
    local w="${1:-58}"
    local line=""
    for ((i=0; i<w; i++)); do line+="─"; done
    echo -e "${C_DIM}${line}${C_RESET}"
}

# ── Show per-session summary ──
show_sessions() {
    # Collect data first to find max for bar scaling
    local -a sess_names=() sess_rss_vals=() sess_cpu_vals=() sess_wins=()
    local max_rss=0

    while IFS= read -r session; do
        local sess_rss=0 sess_cpu="0.0"
        while IFS= read -r pane_pid; do
            local res
            res=$(pane_resources "$pane_pid")
            local rss cpu
            read -r rss cpu <<< "$res"
            sess_rss=$(( sess_rss + rss ))
            sess_cpu=$(awk "BEGIN{printf \"%.1f\", $sess_cpu + $cpu}")
        done < <(tmux list-panes -s -t "$session" -F '#{pane_pid}' 2>/dev/null)
        local win_count
        win_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' ')
        sess_names+=("$session")
        sess_rss_vals+=("$sess_rss")
        sess_cpu_vals+=("$sess_cpu")
        sess_wins+=("$win_count")
        [ "$sess_rss" -gt "$max_rss" ] && max_rss=$sess_rss
    done < <(tmux list-sessions -F '#S' 2>/dev/null)

    # Calculate totals
    local total_rss=0 total_cpu="0.0" total_wins=0
    for ((i=0; i<${#sess_names[@]}; i++)); do
        total_rss=$(( total_rss + sess_rss_vals[i] ))
        total_cpu=$(awk "BEGIN{printf \"%.1f\", $total_cpu + ${sess_cpu_vals[i]}}")
        total_wins=$(( total_wins + sess_wins[i] ))
    done

    {
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}  Session Resources${C_RESET}"
        echo -e "  $(hr 56)"
        echo ""

        for ((i=0; i<${#sess_names[@]}; i++)); do
            local name="${sess_names[i]}"
            local rss="${sess_rss_vals[i]}"
            local cpu="${sess_cpu_vals[i]}"
            local wins="${sess_wins[i]}"
            local mem_str
            mem_str=$(format_mem "$rss")
            local bar
            bar=$(mem_bar "$rss" "$max_rss")
            local cpu_str
            cpu_str=$(cpu_indicator "$cpu")

            echo -e "  ${C_BOLD}${C_WHITE}  ${name}${C_RESET}"
            echo -e "    ${bar}  ${C_BOLD}${mem_str}${C_RESET}  ${cpu_str}  ${C_DIM}${wins} windows${C_RESET}"
            echo ""
        done

        echo -e "  $(hr 56)"
        local total_mem_str
        total_mem_str=$(format_mem "$total_rss")
        echo -e "  ${C_DIM}Total:${C_RESET} ${C_BOLD}${total_mem_str}${C_RESET}  ${total_cpu}% CPU  ${total_wins} windows  ${#sess_names[@]} sessions"
        echo ""
    } > "$SYSMON_TMP"

    local total_h=$(( ${#sess_names[@]} * 3 + 8 ))
    [ "$total_h" -lt 12 ] && total_h=12
    [ "$total_h" -gt 35 ] && total_h=35

    tmux display-popup -w 64 -h "$total_h" -T "  Sessions" \
        -E "less -R $SYSMON_TMP"
}

# ── Show per-window detail for current session ──
show_windows() {
    local session
    session=$(tmux display-message -p '#S' 2>/dev/null)

    local -a win_idxs=() win_names=() win_rss_vals=() win_cpu_vals=() win_procs=()
    local max_rss=0

    while IFS=$'\t' read -r win_idx win_name; do
        local win_rss=0 win_cpu="0.0" main_proc=""
        while IFS=$'\t' read -r pane_pid pane_cmd; do
            local res
            res=$(pane_resources "$pane_pid")
            local rss cpu
            read -r rss cpu <<< "$res"
            win_rss=$(( win_rss + rss ))
            win_cpu=$(awk "BEGIN{printf \"%.1f\", $win_cpu + $cpu}")
            [ -z "$main_proc" ] && main_proc="$pane_cmd"
        done < <(tmux list-panes -t "${session}:${win_idx}" -F '#{pane_pid}	#{pane_current_command}' 2>/dev/null)
        win_idxs+=("$win_idx")
        win_names+=("$win_name")
        win_rss_vals+=("$win_rss")
        win_cpu_vals+=("$win_cpu")
        win_procs+=("$main_proc")
        [ "$win_rss" -gt "$max_rss" ] && max_rss=$win_rss
    done < <(tmux list-windows -t "$session" -F '#{window_index}	#{window_name}' 2>/dev/null)

    {
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}  Windows in ${C_MAGENTA}${session}${C_RESET}"
        echo -e "  $(hr 66)"
        echo ""

        for ((i=0; i<${#win_idxs[@]}; i++)); do
            local idx="${win_idxs[i]}"
            local name="${win_names[i]}"
            local rss="${win_rss_vals[i]}"
            local cpu="${win_cpu_vals[i]}"
            local proc="${win_procs[i]}"
            local mem_str
            mem_str=$(format_mem "$rss")
            local bar
            bar=$(mem_bar "$rss" "$max_rss")
            local cpu_str
            cpu_str=$(cpu_indicator "$cpu")

            [ ${#name} -gt 20 ] && name="${name:0:18}.."
            [ ${#proc} -gt 12 ] && proc="${proc:0:10}.."

            echo -e "  ${C_BOLD}${C_WHITE}${idx}${C_RESET}${C_DIM}:${C_RESET}${C_BOLD}${name}${C_RESET}  ${C_DIM}(${proc})${C_RESET}"
            echo -e "    ${bar}  ${C_BOLD}${mem_str}${C_RESET}  ${cpu_str}"
            echo ""
        done
    } > "$SYSMON_TMP"

    local total_h=$(( ${#win_idxs[@]} * 3 + 6 ))
    [ "$total_h" -lt 10 ] && total_h=10
    [ "$total_h" -gt 35 ] && total_h=35

    tmux display-popup -w 74 -h "$total_h" -T "  Windows [$session]" \
        -E "less -R $SYSMON_TMP"
}

# ── Show all panes with detail ──
show_panes() {
    local session
    session=$(tmux display-message -p '#S' 2>/dev/null)

    local -a pane_labels=() pane_cmds=() pane_rss_vals=() pane_cpu_vals=() pane_pids=()
    local max_rss=0

    while IFS=$'\t' read -r win_idx pane_idx pane_pid pane_cmd; do
        local res
        res=$(pane_resources "$pane_pid")
        local rss cpu
        read -r rss cpu <<< "$res"
        pane_labels+=("${win_idx}:${pane_idx}")
        pane_cmds+=("$pane_cmd")
        pane_rss_vals+=("$rss")
        pane_cpu_vals+=("$cpu")
        pane_pids+=("$pane_pid")
        [ "$rss" -gt "$max_rss" ] && max_rss=$rss
    done < <(tmux list-panes -s -t "$session" -F '#{window_index}	#{pane_index}	#{pane_pid}	#{pane_current_command}' 2>/dev/null)

    {
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}  Panes in ${C_MAGENTA}${session}${C_RESET}"
        echo -e "  $(hr 60)"
        echo ""
        echo -e "  ${C_DIM}  PANE    PROCESS          MEMORY            CPU     PID${C_RESET}"
        echo ""

        for ((i=0; i<${#pane_labels[@]}; i++)); do
            local label="${pane_labels[i]}"
            local cmd="${pane_cmds[i]}"
            local rss="${pane_rss_vals[i]}"
            local cpu="${pane_cpu_vals[i]}"
            local pid="${pane_pids[i]}"
            local mem_str
            mem_str=$(format_mem "$rss")
            local bar
            bar=$(mem_bar "$rss" "$max_rss")
            local cpu_str
            cpu_str=$(cpu_indicator "$cpu")

            [ ${#cmd} -gt 12 ] && cmd="${cmd:0:10}.."

            printf "  ${C_BOLD}${C_WHITE}%-7s${C_RESET} " "$label"
            printf "%-12s  " "$cmd"
            echo -e "${bar} ${C_BOLD}${mem_str}${C_RESET}  ${cpu_str}  ${C_DIM}${pid}${C_RESET}"
        done

        echo ""
    } > "$SYSMON_TMP"

    local total_h=$(( ${#pane_labels[@]} + 9 ))
    [ "$total_h" -lt 10 ] && total_h=10
    [ "$total_h" -gt 35 ] && total_h=35

    tmux display-popup -w 68 -h "$total_h" -T "  Panes [$session]" \
        -E "less -R $SYSMON_TMP"
}

# ── Interactive menu ──
show_menu() {
    tmux display-menu -T "  System Monitor" \
        "Sessions Overview" "s" "run-shell '$CURRENT_DIR/sysmon.sh sessions'" \
        "Windows (this session)" "w" "run-shell '$CURRENT_DIR/sysmon.sh windows'" \
        "Panes (this session)" "p" "run-shell '$CURRENT_DIR/sysmon.sh panes'" \
        "" "" "" \
        "Cancel" "q" ""
}

case "${1:-menu}" in
    sessions) show_sessions ;;
    windows)  show_windows ;;
    panes)    show_panes ;;
    menu)     show_menu ;;
    *)        echo "Usage: sysmon.sh {menu|sessions|windows|panes}"; exit 1 ;;
esac
