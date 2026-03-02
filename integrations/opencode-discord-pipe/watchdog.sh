#!/bin/bash
# opencode-discord-pipe — Watchdog (called by cron)
#
# Checks if the pipe daemon is running. If not, starts it.
# Designed to be called by OpenClaw cron or system cron.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/pipe.pid"

export PATH="/home/node/.local/share/mise/shims:$PATH"
# Discord bot token from environment
export DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
export OPENCODE_URL="${OPENCODE_URL:-http://localhost:4096}"

# Check if OpenCode server is reachable first
if ! curl -s --connect-timeout 2 "$OPENCODE_URL/session" >/dev/null 2>&1; then
  echo "[watchdog] OpenCode server not reachable at $OPENCODE_URL — skipping"
  exit 0
fi

# Check if daemon is running
if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    # Running fine
    exit 0
  fi
  # Stale PID
  rm -f "$PID_FILE"
fi

echo "[watchdog] Pipe not running — starting daemon..."
"$SCRIPT_DIR/daemon.sh" start
