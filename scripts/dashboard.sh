#!/usr/bin/env bash
# dashboard.sh — Start/stop the web dashboard

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
WEB_DIR="$CURRENT_DIR/../web"
PID_FILE="/tmp/flow_tmux_dashboard.pid"
PORT="${FLOW_PORT:-3777}"

start_dashboard() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        flow_message "info" "Dashboard already running on :$PORT"
        return
    fi
    cd "$WEB_DIR"
    bun run server.ts &>/tmp/flow-web.log &
    echo $! > "$PID_FILE"
    sleep 0.5
    local ip
    ip=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    flow_message "info" "󱎫 Dashboard: http://$ip:$PORT"
}

stop_dashboard() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
        flow_message "info" "Dashboard stopped"
    else
        flow_message "info" "Dashboard not running"
    fi
}

case "${1:-}" in
    start) start_dashboard ;;
    stop)  stop_dashboard ;;
    toggle)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            stop_dashboard
        else
            start_dashboard
        fi ;;
    *) echo "Usage: dashboard.sh {start|stop|toggle}"; exit 1 ;;
esac
