#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# gated-execute.sh — Execution wrapper caught by Gateway approval system
#
# This script is the critical human-in-the-loop enforcement point.
# When invoked, it is intercepted by OpenClaw Gateway's exec approval system.
# The Gateway:
#   1. Detects this script name in the exec call (sessionFilter: ["gated-execute"])
#   2. Posts approval request to Discord channel
#   3. Blocks until human sends /approve (or /deny)
#   4. Only then does this script actually execute
#
# Security: Agent cannot bypass this because the Gateway runs OUTSIDE the container.
# The agent can call gated-execute.sh, but execution is held by Gateway until approved.
#
# Usage:
#   gated-execute.sh <task-id> <workspace> <session-id>
#
# Exit codes:
#   0 — Execution started successfully
#   1 — Invalid arguments or task not found
#   2 — Workspace not found
#   3 — Script dependency error

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Logging ---
log() {
  echo "[gated-execute] $*" >&2
}

# --- Validation ---
if [ $# -lt 3 ]; then
  log "Usage: gated-execute.sh <task-id> <workspace> <session-id>"
  log "ERROR: Missing required arguments"
  exit 1
fi

TASK_ID="$1"
TASK_WORKSPACE="$2"
SESSION_ID="$3"

# Validate task ID format (prevent path traversal)
if [[ ! "$TASK_ID" =~ ^task-[0-9]{10,13}-[a-f0-9]{4,8}$ ]]; then
  log "ERROR: Invalid task ID format: $TASK_ID"
  log "Expected format: task-{timestamp}-{hex}"
  exit 1
fi

# Validate workspace exists
if [[ -z "$TASK_WORKSPACE" || ! -d "$TASK_WORKSPACE" ]]; then
  log "ERROR: Workspace not found: $TASK_WORKSPACE"
  exit 2
fi

# Validate session ID (basic format check)
if [[ ! "$SESSION_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
  log "ERROR: Invalid session ID format: $SESSION_ID"
  exit 1
fi

# Validate required scripts exist
for script in opencode-session.sh task-manager.sh; do
  if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
    log "ERROR: Required script not found or not executable: $SCRIPT_DIR/$script"
    exit 3
  fi
done

# Verify task is in approved state (defense-in-depth)
# Note: execute-task.sh holds the TOCTOU lock, this is secondary validation
TASK_JSON=$(bash "$SCRIPT_DIR/task-manager.sh" get "$TASK_ID" 2>/dev/null) || {
  log "ERROR: Task $TASK_ID not found"
  exit 1
}
STATUS=$(echo "$TASK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")
if [[ "$STATUS" != "approved" && "$STATUS" != "executing" ]]; then
  log "ERROR: Task $TASK_ID is in '$STATUS' state, expected 'approved' or 'executing'"
  exit 1
fi

# --- Main Execution (only reached after Gateway approval) ---
log "Approved execution starting for task $TASK_ID"
log "Workspace: $TASK_WORKSPACE"
log "Session: $SESSION_ID"

# Ensure .sisyphus symlink points to the task workspace
WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"
ln -sf "$TASK_WORKSPACE/.sisyphus" "$WORKSPACES_ROOT/.sisyphus" 2>/dev/null || true

# Send /start-work to the OpenCode session to trigger Atlas agent
log "Sending /start-work to session..."
bash "$SCRIPT_DIR/opencode-session.sh" send "$SESSION_ID" - --workspace "$TASK_WORKSPACE" <<< "/start-work"

# Transition task to executing state
log "Updating task state to executing..."
bash "$SCRIPT_DIR/task-manager.sh" status "$TASK_ID" executing
bash "$SCRIPT_DIR/task-manager.sh" update "$TASK_ID" agent_state "atlas"

log "Execution started successfully"
echo "Execution started. Session: $SESSION_ID"
