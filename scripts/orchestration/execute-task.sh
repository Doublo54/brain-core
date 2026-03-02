#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# execute-task.sh — Guarded execution trigger with approval gate
#
# Entry point for starting task execution after plan approval.
# Validates task state, creates session, and routes through approval gate.
#
# Security features:
#   - Task ID format validation (prevents path traversal)
#   - Status verification (must be "approved")
#   - 24-hour approval freshness check
#   - Auto-approve bypass for trusted tasks
#   - --force flag for manual override (testing/trusted scenarios)
#
# Usage:
#   execute-task.sh <task-id> [--force]
#
# Options:
#   --force    Skip approval gate (for testing or trusted manual execution)
#
# Exit codes:
#   0 — Execution triggered (pending approval or auto-approved)
#   1 — Invalid arguments or validation failure
#   2 — Task not found
#   3 — Invalid task state (not approved)
#   4 — Workspace error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(pwd)}"
WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"
STATE_DIR="${STATE_DIR:-${WORKSPACE}/state}"
LOCK_DIR="$STATE_DIR/locks"

log() {
  echo "[execute-task] $*" >&2
}

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Parse arguments
TASK_ID=""
FORCE_FLAG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE_FLAG=true
      shift
      ;;
    -*)
      log "ERROR: Unknown option: $1"
      log "Usage: execute-task.sh <task-id> [--force]"
      exit 1
      ;;
    *)
      if [[ -z "$TASK_ID" ]]; then
        TASK_ID="$1"
      else
        log "ERROR: Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  log "Usage: execute-task.sh <task-id> [--force]"
  exit 1
fi

# 0. Validate TASK_ID format (prevents path traversal)
if [[ ! "$TASK_ID" =~ ^task-[0-9]{10,13}-[a-f0-9]{4,8}$ ]]; then
  log "ERROR: Invalid task ID format: $TASK_ID"
  log "Expected format: task-{timestamp}-{hex}"
  exit 1
fi

# 1. Acquire exclusive lock to prevent TOCTOU race
LOCK_FILE="$LOCK_DIR/${TASK_ID}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "ERROR: Task $TASK_ID is already being executed (lock held)"
  exit 1
fi
# Lock will be released when script exits (fd 9 closes)

# 2. Get task data
TASK_JSON=$(bash "$SCRIPT_DIR/task-manager.sh" get "$TASK_ID" 2>/dev/null) || {
  log "ERROR: Task $TASK_ID not found"
  exit 2
}

# 3. Verify task status is "approved"
STATUS=$(echo "$TASK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")
if [[ "$STATUS" != "approved" ]]; then
  log "ERROR: Task $TASK_ID is in '$STATUS' state, not 'approved'"
  log "Task must be approved before execution can start"
  exit 3
fi

# 4. Get workspace and validate it exists
TASK_WORKSPACE=$(echo "$TASK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('workspace',''))")
if [[ -z "$TASK_WORKSPACE" || ! -d "$TASK_WORKSPACE" ]]; then
  log "ERROR: Workspace not found for task $TASK_ID: $TASK_WORKSPACE"
  exit 4
fi

# 5. Check approval freshness (24-hour limit)
# Use approved_at (set when task transitions to 'approved'), not updated_at (changes on any update)
APPROVED_AT=$(echo "$TASK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('approved_at',''))")
APPROVAL_FRESH=$(python3 -c "
from datetime import datetime, timezone, timedelta
import sys

approved_str = sys.argv[1]
if not approved_str:
    print('false')
    sys.exit(0)

try:
    approved = datetime.fromisoformat(approved_str.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    age = now - approved
    # Approval is fresh if less than 24 hours old
    print('true' if age < timedelta(hours=24) else 'false')
except:
    print('false')
" "$APPROVED_AT")

if [[ "$APPROVAL_FRESH" != "true" ]]; then
  log "ERROR: Approval is stale (>24 hours old) or task was never approved. Please re-approve the task."
  exit 3
fi

# 6. Check auto-approve flag or force flag
AUTO_APPROVE=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('auto_approve', False)).lower())")
SKIP_GATE=false
if [[ "$AUTO_APPROVE" == "true" ]]; then
  SKIP_GATE=true
  log "Auto-approve enabled"
elif [[ "$FORCE_FLAG" == "true" ]]; then
  SKIP_GATE=true
  log "Force flag enabled, skipping approval gate"
fi

# 7. Create OpenCode session for atlas agent
log "Creating OpenCode session..."
SESSION_ID=$(bash "$SCRIPT_DIR/opencode-session.sh" create)
if [[ -z "$SESSION_ID" ]]; then
  log "ERROR: Failed to create OpenCode session"
  exit 4
fi
bash "$SCRIPT_DIR/task-manager.sh" update "$TASK_ID" session_id "$SESSION_ID" >/dev/null

# 8. Capture pre-execution SHA for potential rollback
PRE_SHA=$(cd "$TASK_WORKSPACE" && git rev-parse HEAD 2>/dev/null || echo "")
if [[ -n "$PRE_SHA" ]]; then
  bash "$SCRIPT_DIR/task-manager.sh" update "$TASK_ID" pre_execution_sha "$PRE_SHA" >/dev/null
fi

# 9. Execute through approval gate (or bypass if auto-approved/forced)
if [[ "$SKIP_GATE" == "true" ]]; then
  # Direct execution - bypass approval gate
  # Note: symlink created here for direct execution path
  ln -sf "$TASK_WORKSPACE/.sisyphus" "$WORKSPACES_ROOT/.sisyphus" 2>/dev/null || true
  
  bash "$SCRIPT_DIR/opencode-session.sh" send "$SESSION_ID" - --workspace "$TASK_WORKSPACE" <<< "/start-work"
  bash "$SCRIPT_DIR/task-manager.sh" status "$TASK_ID" executing >/dev/null
  bash "$SCRIPT_DIR/task-manager.sh" update "$TASK_ID" agent_state "atlas" >/dev/null
  
  log "Execution started (gate bypassed). Session: $SESSION_ID"
else
  log "Routing through approval gate..."
  # gated-execute.sh handles symlink creation and /start-work
  # If Gateway approval is configured, this call will be intercepted
  # Otherwise, it executes directly
  bash "$SCRIPT_DIR/gated-execute.sh" "$TASK_ID" "$TASK_WORKSPACE" "$SESSION_ID"
fi

echo "Execution triggered. Session: $SESSION_ID"
