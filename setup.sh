#!/usr/bin/env bash

PORT=18000
PIDFILE=".serve.pid"
LOGFILE="serve.log"

get_local_ip() {
    # Try Linux first, then macOS, then fall back to localhost
    ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' \
    || ipconfig getifaddr en0 2>/dev/null \
    || ipconfig getifaddr en1 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}' \
    || echo "127.0.0.1"
}

port_pid() {
    # Return the PID of whatever process is bound to $PORT (empty if none)
    ss -tlnp "sport = :$PORT" 2>/dev/null \
        | grep -oP 'pid=\K[0-9]+' \
        | head -1
}

is_running() {
    # True when something is actually listening on the port
    [ -n "$(port_pid)" ]
}

start_service() {
    echo ""
    if is_running; then
        echo "  ↻  Service already running — restarting..."
        stop_service
    fi

    nohup python3 -u serve.py > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"

    # Wait up to 3 seconds for the port to open
    local i=0
    while [ $i -lt 6 ]; do
        is_running && break
        sleep 0.5
        i=$((i + 1))
    done

    if is_running; then
        local ip
        ip=$(get_local_ip)
        echo "  ✅  Service started (PID $(cat $PIDFILE))"
        echo "  🌐  UI: https://$ip:$PORT/"
        echo "  📄  Logs: $LOGFILE"
    else
        echo "  ❌  Failed to start — check $LOGFILE for details"
        tail -5 "$LOGFILE" 2>/dev/null | sed 's/^/      /'
    fi
    echo ""
}

stop_service() {
    echo ""
    local pid
    pid=$(port_pid)

    if [ -z "$pid" ]; then
        echo "  ⚠️   Service is not running"
        rm -f "$PIDFILE"
        echo ""
        return
    fi

    echo "  🛑  Stopping PID $pid..."
    kill "$pid" 2>/dev/null

    # Wait up to 5 seconds for the port to actually close
    local i=0
    while [ $i -lt 10 ]; do
        sleep 0.5
        is_running || break
        i=$((i + 1))
    done

    # Force-kill if still alive
    if is_running; then
        echo "  ⚡  SIGTERM timed out — sending SIGKILL..."
        kill -9 "$pid" 2>/dev/null
        sleep 0.5
    fi

    if is_running; then
        echo "  ❌  Could not stop service (PID $(port_pid) still on port $PORT)"
    else
        echo "  ✅  Service stopped"
    fi

    rm -f "$PIDFILE"
    echo ""
}

service_status() {
    echo ""
    local pid
    pid=$(port_pid)

    if [ -n "$pid" ]; then
        local ip
        ip=$(get_local_ip)
        echo "  ✅  Service is running"
        echo "  🔢  PID:  $pid"
        echo "  🌐  URL:  https://$ip:$PORT/"

        # Uptime via /proc
        if [ -f "/proc/$pid/stat" ]; then
            local start_ticks uptime_sec btime elapsed
            start_ticks=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)
            btime=$(awk '/^btime/{print $2}' /proc/stat 2>/dev/null)
            if [ -n "$start_ticks" ] && [ -n "$btime" ]; then
                local hz; hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
                elapsed=$(( $(date +%s) - btime - start_ticks / hz ))
                local h=$((elapsed/3600)) m=$(( (elapsed%3600)/60 )) s=$((elapsed%60))
                printf "  ⏱️   Up:   %dh %02dm %02ds\n" "$h" "$m" "$s"
            fi
        fi

        # HTTP reachability
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 -k "https://127.0.0.1:$PORT/" 2>/dev/null)
        if [ "$http_code" = "200" ]; then
            echo "  💚  HTTP: OK (200)"
        else
            echo "  ⚠️   HTTP: unexpected response (HTTP ${http_code:-timeout})"
        fi
    else
        echo "  🔴  Service is NOT running"
    fi

    # Last 5 log lines (always shown)
    if [ -f "$LOGFILE" ] && [ -s "$LOGFILE" ]; then
        echo "  ─────────────────────────────────"
        echo "  📄  Last log lines ($LOGFILE):"
        tail -5 "$LOGFILE" | sed 's/^/      /'
    fi
    echo ""
}

# ── Menu ───────────────────────────────────────────────────────────────────────

while true; do
    echo "╔══════════════════════════════════╗"
    echo "║       Autism Q&A UI Server       ║"
    echo "╠══════════════════════════════════╣"
    echo "║  1) Start / Restart service      ║"
    echo "║  2) Stop service                 ║"
    echo "║  3) Service status               ║"
    echo "║  0) Exit                         ║"
    echo "╚══════════════════════════════════╝"
    printf "  Choose an option: "
    read -r choice

    case "$choice" in
        1) start_service ;;
        2) stop_service ;;
        3) service_status ;;
        0) echo ""; echo "  Bye!"; echo ""; exit 0 ;;
        *) echo ""; echo "  ⚠️  Invalid option, try again."; echo "" ;;
    esac
done
