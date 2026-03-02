#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# daemon-monitor.sh — background monitoring daemon
# Runs monitor.sh and watchdog checks without LLM involvement
# Alerts written to state/alerts.json for the orchestrator to check on session start

set -euo pipefail

WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/scripts/orchestration}"
PIDFILE="$WORKSPACE/state/monitor-daemon.pid"
LOGFILE="$WORKSPACE/state/monitor-daemon.log"

MONITOR_INTERVAL=60      # monitor.sh every 60s
WATCHDOG_INTERVAL=300    # watchdog every 5min
CLEANUP_INTERVAL=21600   # session cleanup every 6h (21600s)
SESSION_RETENTION_HOURS=48  # session age threshold for cleanup
SCRIPT_TIMEOUT=120       # timeout for child scripts (seconds)

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOGFILE"
}

cleanup() {
  log "Daemon stopping (signal received)"
  rm -f "$PIDFILE"
  exit 0
}

trap cleanup SIGTERM SIGINT

# Helper: validate PID is numeric and positive
is_valid_pid() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" -gt 0 ]]
}

# Commands
start_daemon() {
  # Ensure state directory exists
  mkdir -p "$(dirname "$PIDFILE")" || { echo "ERROR: Cannot create state dir"; exit 1; }
  
  # Check if already running
  if [[ -f "$PIDFILE" ]]; then
    local old_pid
    old_pid=$(cat "$PIDFILE" 2>/dev/null | tr -d '[:space:]')
    if is_valid_pid "$old_pid" && kill -0 "$old_pid" 2>/dev/null; then
      echo "Daemon already running (PID $old_pid)"
      exit 0
    fi
    rm -f "$PIDFILE"
  fi

  # Write PID file (use BASHPID for correct PID in subshell)
  echo "${BASHPID:-$$}" > "$PIDFILE"
  log "Daemon started (PID ${BASHPID:-$$})"
  
  local last_monitor=0
  local last_watchdog=0
  local last_cleanup=0
  
  while true; do
    local now
    now=$(date +%s)
    
    # Run monitor.sh every MONITOR_INTERVAL
    if (( now - last_monitor >= MONITOR_INTERVAL )); then
      log "Running monitor.sh"
      if bash "$SCRIPTS_DIR/monitor.sh" >> "$LOGFILE" 2>&1; then
        log "monitor.sh completed successfully"
      else
        log "monitor.sh exited with code $?"
      fi
      last_monitor=$now
    fi
    
    # Run watchdog every WATCHDOG_INTERVAL
    if (( now - last_watchdog >= WATCHDOG_INTERVAL )); then
      log "Running watchdog"
      if bash "$WORKSPACE/opencode-discord-pipe/watchdog-cron.sh" >> "$LOGFILE" 2>&1; then
        log "watchdog completed successfully"
      else
        log "watchdog exited with code $?"
      fi
      last_watchdog=$now
    fi
    
    # Run session cleanup every CLEANUP_INTERVAL (6h default)
    if (( now - last_cleanup >= CLEANUP_INTERVAL )); then
      log "Running session cleanup (age: ${SESSION_RETENTION_HOURS}h)"
      if timeout ${SCRIPT_TIMEOUT} bash "$SCRIPTS_DIR/opencode-session-cleanup.sh" "$SESSION_RETENTION_HOURS" >> "$LOGFILE" 2>&1; then
        log "session cleanup completed successfully"
      else
        log "session cleanup exited with code $?"
      fi
      
      log "Running orphan cleanup"
      if timeout ${SCRIPT_TIMEOUT} bash "$SCRIPTS_DIR/opencode-orphan-cleanup.sh" >> "$LOGFILE" 2>&1; then
        log "orphan cleanup completed successfully"
      else
        log "orphan cleanup exited with code $?"
      fi
      last_cleanup=$now
    fi
    
    sleep 10
  done
}

stop_daemon() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "Daemon not running (no PID file)"
    return 0
  fi
  
  local pid
  pid=$(cat "$PIDFILE" 2>/dev/null | tr -d '[:space:]')
  
  if ! is_valid_pid "$pid"; then
    echo "Invalid PID in file, removing"
    rm -f "$PIDFILE"
    return 0
  fi
  
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Daemon not running (stale PID file)"
    rm -f "$PIDFILE"
    return 0
  fi
  
  echo "Stopping daemon (PID $pid)..."
  kill -TERM "$pid"
  
  # Wait for clean exit
  local retries=10
  while kill -0 "$pid" 2>/dev/null && (( retries > 0 )); do
    sleep 1
    retries=$((retries - 1))
  done
  
  if kill -0 "$pid" 2>/dev/null; then
    echo "Force killing..."
    kill -KILL "$pid" 2>/dev/null || true
  fi
  
  rm -f "$PIDFILE"
  echo "Daemon stopped"
}

status_daemon() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "Daemon not running (no PID file)"
    exit 1
  fi
  
  local pid
  pid=$(cat "$PIDFILE" 2>/dev/null | tr -d '[:space:]')
  
  if ! is_valid_pid "$pid"; then
    echo "Invalid PID in file"
    exit 1
  fi
  
  if kill -0 "$pid" 2>/dev/null; then
    echo "Daemon running (PID $pid)"
    echo "Log tail:"
    tail -5 "$LOGFILE" 2>/dev/null || echo "(no log)"
    exit 0
  else
    echo "Daemon not running (stale PID file)"
    rm -f "$PIDFILE"
    exit 1
  fi
}

# Foreground mode for testing
run_foreground() {
  echo "Running in foreground (Ctrl+C to stop)..."
  # Use local PIDFILE to avoid cleanup trap trying to delete /dev/null
  local PIDFILE="/dev/null"
  
  local last_monitor=0
  local last_watchdog=0
  local last_cleanup=0
  
  while true; do
    local now
    now=$(date +%s)
    
    if (( now - last_monitor >= MONITOR_INTERVAL )); then
      echo "[$(date -u +%H:%M:%S)] Running monitor.sh"
      bash "$SCRIPTS_DIR/monitor.sh" 2>&1 || echo "monitor.sh failed"
      last_monitor=$now
    fi
    
    if (( now - last_watchdog >= WATCHDOG_INTERVAL )); then
      echo "[$(date -u +%H:%M:%S)] Running watchdog"
      bash "$WORKSPACE/opencode-discord-pipe/watchdog-cron.sh" 2>&1 || echo "watchdog failed"
      last_watchdog=$now
    fi
    
    if (( now - last_cleanup >= CLEANUP_INTERVAL )); then
      echo "[$(date -u +%H:%M:%S)] Running session cleanup (age: ${SESSION_RETENTION_HOURS}h)"
      timeout ${SCRIPT_TIMEOUT} bash "$SCRIPTS_DIR/opencode-session-cleanup.sh" "$SESSION_RETENTION_HOURS" 2>&1 || echo "session cleanup failed"
      echo "[$(date -u +%H:%M:%S)] Running orphan cleanup"
      timeout ${SCRIPT_TIMEOUT} bash "$SCRIPTS_DIR/opencode-orphan-cleanup.sh" 2>&1 || echo "orphan cleanup failed"
      last_cleanup=$now
    fi
    
    sleep 10
  done
}

# Main
case "${1:-}" in
  start)
    # Use nohup + redirect to properly background the daemon
    # The daemon writes its own PID file after starting
    nohup bash "$0" _daemon > /dev/null 2>&1 &
    sleep 2
    if [[ -f "$PIDFILE" ]]; then
      echo "Daemon started (PID $(cat "$PIDFILE"))"
    else
      echo "Daemon may have failed to start, check $LOGFILE"
      exit 1
    fi
    ;;
  _daemon)
    # Internal: actual daemon entry point (called via nohup)
    start_daemon
    ;;
  stop)
    stop_daemon
    ;;
  status)
    status_daemon
    ;;
  restart)
    stop_daemon
    sleep 1
    nohup bash "$0" _daemon > /dev/null 2>&1 &
    sleep 2
    if [[ -f "$PIDFILE" ]]; then
      echo "Daemon restarted (PID $(cat "$PIDFILE"))"
    else
      echo "Daemon may have failed to start"
      exit 1
    fi
    ;;
  run)
    # Foreground mode for testing
    run_foreground
    ;;
  *)
    echo "Usage: $0 {start|stop|status|restart|run}"
    exit 1
    ;;
esac
