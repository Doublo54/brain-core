#!/bin/bash
# opencode-discord-pipe — Startup script
#
# Routes OpenCode SSE events to Discord channels.
# Requires: npx, tsx (via mise shims), DISCORD_BOT_TOKEN env var
#
# Usage: ./start.sh
# Or:    DISCORD_BOT_TOKEN=xxx ./start.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
export OPENCODE_URL="${OPENCODE_URL:-http://localhost:4096}"

if [ -z "$DISCORD_BOT_TOKEN" ]; then
  echo "[start] WARNING: No DISCORD_BOT_TOKEN set — running in dry-run mode (stdout only)"
fi

echo "[start] Starting opencode-discord-pipe..."
echo "[start] OpenCode: $OPENCODE_URL"
echo "[start] Script dir: $SCRIPT_DIR"

# Use locally installed tsx only — no npx fallback (supply-chain risk).
if [ -x "$SCRIPT_DIR/node_modules/.bin/tsx" ]; then
  exec "$SCRIPT_DIR/node_modules/.bin/tsx" "$SCRIPT_DIR/pipe.ts"
else
  echo "[start] ERROR: local tsx not found. Run 'npm install' in $SCRIPT_DIR first."
  exit 1
fi
