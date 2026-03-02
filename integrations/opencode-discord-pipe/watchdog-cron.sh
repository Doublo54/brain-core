#!/bin/bash
# Watchdog for opencode-discord-pipe — run via cron every 5 minutes
# This script is self-contained. No LLM needed. Just checks and restarts.
PIPE_DIR="${PIPE_DIR:-.}"
PID_FILE="$PIPE_DIR/pipe.pid"
CHILD_PID_FILE="$PIPE_DIR/pipe-child.pid"
LOG_FILE="$PIPE_DIR/pipe.log"

log() {
  echo "[watchdog] $(date -u +%Y-%m-%dT%H:%M:%SZ) — $*" >> "$LOG_FILE"
}

# Check 1: Is the daemon process alive?
daemon_alive=false
if [ -f "$PID_FILE" ]; then
  DAEMON_PID=$(cat "$PID_FILE")
  if kill -0 "$DAEMON_PID" 2>/dev/null; then
    daemon_alive=true
  fi
fi

# Check 2: Is the pipe child alive?
child_alive=false
if [ -f "$CHILD_PID_FILE" ]; then
  CHILD_PID=$(cat "$CHILD_PID_FILE")
  if kill -0 "$CHILD_PID" 2>/dev/null; then
    child_alive=true
  fi
fi

# Check 3: Is the pipe.ts process actually running? (belt and suspenders)
pipe_running=false
if pgrep -f "opencode-discord-pipe/pipe.ts" > /dev/null 2>&1; then
  pipe_running=true
fi

# All healthy
if $daemon_alive && $child_alive && $pipe_running; then
  exit 0
fi

# Something is wrong — log what we found
log "Health check failed: daemon=$daemon_alive child=$child_alive pipe=$pipe_running"

# Kill anything stale
if $daemon_alive && ! $child_alive; then
  log "Daemon alive but child dead — stopping daemon first"
  bash "$PIPE_DIR/daemon.sh" stop >> "$LOG_FILE" 2>&1
  sleep 2
fi

# Kill orphan pipe processes (not managed by daemon)
for pid in $(pgrep -f "opencode-discord-pipe/pipe.ts" 2>/dev/null); do
  kill -TERM "$pid" 2>/dev/null
done
sleep 1

# Clean stale PID files
rm -f "$PID_FILE" "$CHILD_PID_FILE"

# Restart via nohup (survives parent shell exit)
log "Restarting daemon..."
export PATH="/home/node/.local/share/mise/shims:$PATH"
export DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
export OPENCODE_URL="${OPENCODE_URL:-http://localhost:4096}"
nohup bash "$PIPE_DIR/daemon.sh" run >> "$LOG_FILE" 2>&1 &

sleep 3

# Verify restart worked
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  log "Restart successful (PID $(cat "$PID_FILE"))"
else
  log "ERROR: Restart failed"
  exit 1
fi
