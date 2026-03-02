#!/bin/bash
# opencode-discord-pipe — Daemon wrapper (foreground process supervisor)
#
# Runs the pipe with auto-restart, healthchecks, and SSE liveness monitoring.
# Primary mode is `run` (foreground) for docker-init / process supervisors.
# `start` wraps `run` in nohup for backward compatibility.
#
# Usage:
#   ./daemon.sh run     — Run in foreground (for docker-init / systemd)
#   ./daemon.sh start   — Start daemon in background (nohup + disown)
#   ./daemon.sh stop    — Stop daemon and pipe child
#   ./daemon.sh restart — Restart daemon
#   ./daemon.sh status  — Check if running (daemon + pipe child)
#   ./daemon.sh logs    — Tail logs

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/pipe.pid"
CHILD_PID_FILE="$SCRIPT_DIR/pipe-child.pid"
LOG_FILE="$SCRIPT_DIR/pipe.log"
MAX_LOG_SIZE=5242880  # 5MB

export DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
export OPENCODE_URL="${OPENCODE_URL:-http://localhost:4096}"

# Load local channel config if present (gitignored, persists locally)
if [ -f "$SCRIPT_DIR/.env.local" ]; then
  set -a
  source "$SCRIPT_DIR/.env.local"
  set +a
fi

# Add mise shims to PATH for npx/node
export PATH="/home/node/.local/share/mise/shims:$PATH"

# ─── Helpers ──────────────────────────────────────────────────────────────────

log() {
  echo "[daemon] $(date -u +%Y-%m-%dT%H:%M:%SZ) — $*"
}

# In foreground mode, log to both stdout and file. In background mode, stdout
# is already redirected to LOG_FILE by nohup, so this just writes to stdout.
log_to_file() {
  echo "[daemon] $(date -u +%Y-%m-%dT%H:%M:%SZ) — $*" >> "$LOG_FILE"
}

rotate_log() {
  if [ -f "$LOG_FILE" ]; then
    local size
    size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "${size:-0}" -gt "$MAX_LOG_SIZE" ]; then
      mv "$LOG_FILE" "${LOG_FILE}.old"
      log_to_file "Log rotated"
    fi
  fi
}

is_running() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    # Stale PID file
    rm -f "$PID_FILE"
  fi
  return 1
}

is_child_alive() {
  if [ -f "$CHILD_PID_FILE" ]; then
    local pid
    pid=$(cat "$CHILD_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

kill_orphan_pipes() {
  # Kill any pipe.ts processes not managed by this daemon (e.g. from docker-compose boot).
  # This prevents duplicate SSE connections that cause duplicate Discord threads.
  local my_pid="${1:-0}"
  local orphans=()
  for pid in $(pgrep -f "pipe\.ts" 2>/dev/null); do
    if [ "$pid" != "$my_pid" ] && [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" != "$my_pid" ]; then
      orphans+=("$pid")
    fi
  done
  [ ${#orphans[@]} -eq 0 ] && return 0

  # SIGTERM first — let shutdown handlers run
  for pid in "${orphans[@]}"; do
    kill -TERM "$pid" 2>/dev/null
  done
  sleep 2

  # SIGKILL any survivors
  local killed=0
  for pid in "${orphans[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null
    fi
    killed=$((killed + 1))
  done
  log "Cleaned up $killed orphan pipe process(es)"
}

# ─── SSE Liveness Check ──────────────────────────────────────────────────────

SSE_FAIL_COUNT=0
SSE_MAX_FAILS=3
SSE_CHECK_INTERVAL=60

check_sse_liveness() {
  # Check if the OpenCode server is responsive. We use /session (REST endpoint)
  # instead of /event (SSE stream) because SSE never completes — curl would
  # always timeout and report failure even when the server is healthy.
  if curl -sf --connect-timeout 5 --max-time 10 \
       "$OPENCODE_URL/session" -o /dev/null 2>/dev/null; then
    SSE_FAIL_COUNT=0
    return 0
  else
    SSE_FAIL_COUNT=$((SSE_FAIL_COUNT + 1))
    log_to_file "SSE liveness check failed ($SSE_FAIL_COUNT/$SSE_MAX_FAILS)"
    if [ "$SSE_FAIL_COUNT" -ge "$SSE_MAX_FAILS" ]; then
      return 1
    fi
    return 0
  fi
}

# ─── Core: Foreground Run ────────────────────────────────────────────────────

do_run() {
  # This is the primary mode. Runs the restart loop as the foreground process.
  # Docker-init, systemd, or any process supervisor should call this directly.

  if is_running; then
    log "Already running (PID $(cat "$PID_FILE")). Use 'stop' first."
    exit 1
  fi

  # Write our own PID (we ARE the daemon in foreground mode)
  echo $$ > "$PID_FILE"
  log "Foreground supervisor started (PID $$)"
  log_to_file "Foreground supervisor started (PID $$)"

  kill_orphan_pipes "$$"
  rotate_log

  # ── Trap: propagate signals to child ──
  PIPE_CHILD_PID=""

  cleanup() {
    log "Received signal, shutting down..."
    log_to_file "Received signal, shutting down..."
    if [ -n "$PIPE_CHILD_PID" ] && kill -0 "$PIPE_CHILD_PID" 2>/dev/null; then
      log "Terminating pipe child (PID $PIPE_CHILD_PID)"
      log_to_file "Terminating pipe child (PID $PIPE_CHILD_PID)"
      kill -TERM "$PIPE_CHILD_PID" 2>/dev/null
      # Wait up to 5s for graceful shutdown
      for _ in $(seq 1 10); do
        kill -0 "$PIPE_CHILD_PID" 2>/dev/null || break
        sleep 0.5
      done
      # Force kill if still alive
      if kill -0 "$PIPE_CHILD_PID" 2>/dev/null; then
        log "Force killing pipe child (PID $PIPE_CHILD_PID)"
        kill -9 "$PIPE_CHILD_PID" 2>/dev/null
      fi
      wait "$PIPE_CHILD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE" "$CHILD_PID_FILE"
    log "Shutdown complete"
    log_to_file "Shutdown complete"
    exit 0
  }

  trap cleanup SIGTERM SIGINT SIGHUP

  # ── Restart loop ──
  CONSECUTIVE_FAST_EXITS=0
  MAX_FAST_EXITS=5
  MIN_RUNTIME_SECS=30

  while true; do
    START_TIME=$(date +%s)
    log "Starting pipe..."
    log_to_file "Starting pipe..."

    rotate_log

    # Launch the pipe as a background child so we can monitor it
    "$SCRIPT_DIR/node_modules/.bin/tsx" "$SCRIPT_DIR/pipe.ts" >> "$LOG_FILE" 2>&1 &
    PIPE_CHILD_PID=$!
    echo "$PIPE_CHILD_PID" > "$CHILD_PID_FILE"
    log "Pipe started (child PID $PIPE_CHILD_PID)"
    log_to_file "Pipe started (child PID $PIPE_CHILD_PID)"

    SSE_FAIL_COUNT=0
    local last_health_check=$SECONDS
    local last_sse_check=$SECONDS

    # ── Monitor loop: wait for child, checking health periodically ──
    while true; do
      # Non-blocking check: is the child still running?
      if ! kill -0 "$PIPE_CHILD_PID" 2>/dev/null; then
        # Child exited — reap it
        wait "$PIPE_CHILD_PID" 2>/dev/null
        EXIT_CODE=$?
        break
      fi

      # Healthcheck: verify child is alive every 30s
      local now=$SECONDS
      if (( now - last_health_check >= 30 )); then
        last_health_check=$now
        if ! kill -0 "$PIPE_CHILD_PID" 2>/dev/null; then
          log_to_file "Healthcheck: child PID $PIPE_CHILD_PID is dead (zombie/reaped)"
          wait "$PIPE_CHILD_PID" 2>/dev/null
          EXIT_CODE=1
          break
        fi
      fi

      # SSE liveness check every 60s
      if (( now - last_sse_check >= SSE_CHECK_INTERVAL )); then
        last_sse_check=$now
        if ! check_sse_liveness; then
          log "SSE endpoint failed $SSE_MAX_FAILS consecutive checks — force-restarting pipe"
          log_to_file "SSE endpoint failed $SSE_MAX_FAILS consecutive checks — force-restarting pipe"
          kill -TERM "$PIPE_CHILD_PID" 2>/dev/null
          sleep 2
          if kill -0 "$PIPE_CHILD_PID" 2>/dev/null; then
            kill -9 "$PIPE_CHILD_PID" 2>/dev/null
          fi
          wait "$PIPE_CHILD_PID" 2>/dev/null
          EXIT_CODE=1
          break
        fi
      fi

      # Sleep in short bursts so we respond to signals quickly
      sleep 5 &
      wait $! 2>/dev/null || true
    done

    END_TIME=$(date +%s)
    RUNTIME=$((END_TIME - START_TIME))
    rm -f "$CHILD_PID_FILE"
    PIPE_CHILD_PID=""

    log "Pipe exited (code $EXIT_CODE, ran ${RUNTIME}s)"
    log_to_file "Pipe exited with code $EXIT_CODE after ${RUNTIME}s"

    # Only stop on explicit signal (SIGTERM/SIGINT forwarded to child)
    if [ "$EXIT_CODE" -eq 143 ] || [ "$EXIT_CODE" -eq 130 ]; then
      log "Signal stop (code $EXIT_CODE), not restarting"
      log_to_file "Signal stop (code $EXIT_CODE), not restarting"
      rm -f "$PID_FILE" "$CHILD_PID_FILE"
      break
    fi

    # Track fast exits to prevent infinite crash loops
    if [ "$RUNTIME" -lt "$MIN_RUNTIME_SECS" ]; then
      CONSECUTIVE_FAST_EXITS=$((CONSECUTIVE_FAST_EXITS + 1))
      log "Fast exit ($CONSECUTIVE_FAST_EXITS/$MAX_FAST_EXITS)"
      log_to_file "Fast exit ($CONSECUTIVE_FAST_EXITS/$MAX_FAST_EXITS)"
      if [ "$CONSECUTIVE_FAST_EXITS" -ge "$MAX_FAST_EXITS" ]; then
        log "Too many fast exits, giving up"
        log_to_file "Too many fast exits, giving up"
        rm -f "$PID_FILE" "$CHILD_PID_FILE"
        break
      fi
    else
      CONSECUTIVE_FAST_EXITS=0
    fi

    # Backoff: 5s base, doubles on consecutive fast exits (max 60s)
    BACKOFF=$((5 * (1 << (CONSECUTIVE_FAST_EXITS > 0 ? CONSECUTIVE_FAST_EXITS - 1 : 0))))
    [ "$BACKOFF" -gt 60 ] && BACKOFF=60
    log "Restarting in ${BACKOFF}s..."
    log_to_file "Restarting in ${BACKOFF}s..."
    sleep "$BACKOFF" &
    wait $! 2>/dev/null || true

    # Kill any orphans that may have appeared
    kill_orphan_pipes "$$"
  done
}

# ─── Start (background wrapper) ──────────────────────────────────────────────

do_start() {
  if is_running; then
    log "Already running (PID $(cat "$PID_FILE"))"
    return 0
  fi

  log "Starting opencode-discord-pipe in background..."
  rotate_log

  nohup bash "$0" run >> "$LOG_FILE" 2>&1 &
  disown
  local daemon_pid=$!
  # Give the run command a moment to write its own PID file
  sleep 1

  # If run didn't write PID yet, write the nohup wrapper's PID
  if [ ! -f "$PID_FILE" ]; then
    echo "$daemon_pid" > "$PID_FILE"
  fi

  log "Started (PID $(cat "$PID_FILE"))"
  log "Logs: $LOG_FILE"
}

# ─── Stop ─────────────────────────────────────────────────────────────────────

do_stop() {
  if ! is_running; then
    log "Not running"
    # Clean up child PID file if stale
    rm -f "$CHILD_PID_FILE"
    return 0
  fi

  local daemon_pid
  daemon_pid=$(cat "$PID_FILE")
  log "Stopping daemon PID $daemon_pid..."

  # Kill daemon first (sends SIGTERM which triggers cleanup trap)
  kill -TERM "$daemon_pid" 2>/dev/null

  # Wait up to 8s for graceful shutdown (daemon needs to kill child + wait)
  for _ in $(seq 1 16); do
    if ! kill -0 "$daemon_pid" 2>/dev/null; then
      rm -f "$PID_FILE" "$CHILD_PID_FILE"
      log "Stopped"
      return 0
    fi
    sleep 0.5
  done

  # Force kill daemon and any remaining children
  log "Force killing daemon PID $daemon_pid..."
  kill -9 "$daemon_pid" 2>/dev/null
  pkill -9 -P "$daemon_pid" 2>/dev/null

  # Also kill the pipe child if it's still around
  if [ -f "$CHILD_PID_FILE" ]; then
    local child_pid
    child_pid=$(cat "$CHILD_PID_FILE")
    if kill -0 "$child_pid" 2>/dev/null; then
      log "Force killing pipe child PID $child_pid..."
      kill -9 "$child_pid" 2>/dev/null
    fi
  fi

  rm -f "$PID_FILE" "$CHILD_PID_FILE"
  log "Force killed"
}

# ─── Status ───────────────────────────────────────────────────────────────────

do_status() {
  local daemon_alive=false
  local child_alive=false
  local daemon_pid=""
  local child_pid=""

  if [ -f "$PID_FILE" ]; then
    daemon_pid=$(cat "$PID_FILE")
    if kill -0 "$daemon_pid" 2>/dev/null; then
      daemon_alive=true
    fi
  fi

  if [ -f "$CHILD_PID_FILE" ]; then
    child_pid=$(cat "$CHILD_PID_FILE")
    if kill -0 "$child_pid" 2>/dev/null; then
      child_alive=true
    fi
  fi

  if $daemon_alive && $child_alive; then
    echo "[daemon] Running — daemon PID $daemon_pid, pipe child PID $child_pid"
    tail -3 "$LOG_FILE" 2>/dev/null
    return 0
  elif $daemon_alive; then
    echo "[daemon] Daemon running (PID $daemon_pid) but pipe child is NOT alive"
    echo "[daemon] Child may be restarting — check logs"
    tail -5 "$LOG_FILE" 2>/dev/null
    return 0
  else
    echo "[daemon] Not running"
    if $child_alive; then
      echo "[daemon] WARNING: orphan pipe child still alive (PID $child_pid)"
    fi
    # Clean up stale PID files
    [ -n "$daemon_pid" ] && rm -f "$PID_FILE"
    [ -n "$child_pid" ] && ! $child_alive && rm -f "$CHILD_PID_FILE"
    return 1
  fi
}

# ─── Logs ─────────────────────────────────────────────────────────────────────

do_logs() {
  if [ -f "$LOG_FILE" ]; then
    tail -"${1:-50}" "$LOG_FILE"
  else
    echo "[daemon] No log file yet"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-status}" in
  run)     do_run ;;
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; sleep 1; do_start ;;
  status)  do_status ;;
  logs)    do_logs "${2:-50}" ;;
  *)
    echo "Usage: $0 {run|start|stop|restart|status|logs [N]}"
    exit 1
    ;;
esac
