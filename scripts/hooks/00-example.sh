#!/bin/sh
# =============================================================================
# 00-example.sh — Discord Pipe Daemon Hook (example)
#
# Starts the Discord pipe daemon that routes OpenCode SSE events to Discord
# channels. The daemon runs in the background and is managed by a watchdog.
#
# NOTE: OpenCode bootstrap + server are handled by the entrypoint (step 3).
#       This hook runs AFTER OpenCode is ready, so you can depend on it.
#
# To activate: copy this file to /home/node/.openclaw/hooks/00-discord.sh
# =============================================================================

PIPE_DIR="/opt/integrations/opencode-discord-pipe"

if [ -f "$PIPE_DIR/daemon.sh" ] && [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
  echo "[hook:discord-pipe] Starting daemon..."
  bash "$PIPE_DIR/daemon.sh" start &
  echo "[hook:discord-pipe] Daemon started"
else
  echo "[hook:discord-pipe] Skipped (no token or daemon not found)"
fi
