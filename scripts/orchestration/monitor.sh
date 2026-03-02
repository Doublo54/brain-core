#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# monitor.sh — Deterministic monitoring for the orchestrator
#
# Runs via OpenClaw cron every 60s. Handles everything that doesn't need judgment:
# timeouts, nudge, health checks, session cleanup, workspace retention, alerts.
# The orchestrator handles ambiguous decisions via alerts.
#
# Usage:
#   monitor.sh              — run all checks
#   monitor.sh health       — OpenCode health check only
#   monitor.sh tasks        — task checks only (timeouts, idle, nudge)
#   monitor.sh cleanup      — session + workspace cleanup only
#
# Output: JSON summary on stdout
# Logging: progress/errors on stderr
# Alerts: written to state/alerts.json for the orchestrator to consume
#
# Exit codes:
#   0 — All checks passed (or alerts written for the orchestrator)
#   1 — Invalid arguments
#   4 — State file I/O error

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
STATE_DIR="${WORKSPACE}/state"
ALERTS_FILE="${STATE_DIR}/alerts.json"
TASKS_FILE="${STATE_DIR}/tasks.json"
OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:4096}"
WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"

# Health check state (persistent across runs via file)
HEALTH_STATE_FILE="${STATE_DIR}/.health_failures"

# Default timeouts (overridden by repo config if available)
DEFAULT_PLANNING_MIN=60
DEFAULT_EXECUTION_MIN=240
DEFAULT_IDLE_MIN=10
DEFAULT_TOTAL_MIN=480

# Retention
RETENTION_FAILED_HOURS=48

# --- Logging ---
log() {
  echo "[monitor] $*" >&2
}

# --- Ensure state files exist ---
ensure_state() {
  mkdir -p "$STATE_DIR"

  if [ ! -f "$TASKS_FILE" ]; then
    echo '{"tasks": {}, "queue": [], "version": 2}' > "$TASKS_FILE"
  fi

  if [ ! -f "$ALERTS_FILE" ]; then
    echo '{"alerts": [], "version": 1}' > "$ALERTS_FILE"
  fi

  if [ ! -f "$HEALTH_STATE_FILE" ]; then
    echo "0" > "$HEALTH_STATE_FILE"
  fi

  # Clean up orphaned .new files from interrupted runs
  rm -f "${STATE_DIR}"/*.new 2>/dev/null || true
}

# --- Alert helpers ---
write_alert() {
  local alert_type="$1"
  local task_id="$2"
  local message="$3"
  local severity="${4:-medium}"

  (
    flock -w 5 201 || { log "WARNING: Could not acquire alert lock"; return; }

    python3 -c "
import json, sys, os
from datetime import datetime, timezone

alerts_file = sys.argv[1]
alert_type = sys.argv[2]
task_id = sys.argv[3]
message = sys.argv[4]
severity = sys.argv[5]

try:
    with open(alerts_file) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {'alerts': [], 'version': 1}

# Don't duplicate alerts — check if same type+task already unresolved
for a in data['alerts']:
    if (a.get('type') == alert_type and
        a.get('task_id') == task_id and
        a.get('resolved_at') is None):
        sys.exit(0)  # Already exists

now = datetime.now(timezone.utc).isoformat()
alert_id = f'alert-{task_id}-{alert_type}'

data['alerts'].append({
    'id': alert_id,
    'type': alert_type,
    'task_id': task_id,
    'message': message,
    'severity': severity,
    'created_at': now,
    'resolved_at': None,
    'resolved_by': None
})

with open(alerts_file + '.new', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename(alerts_file + '.new', alerts_file)
" "$ALERTS_FILE" "$alert_type" "$task_id" "$message" "$severity"

  ) 201>"${STATE_DIR}/.alerts.lock"

  log "ALERT [$severity] $alert_type for $task_id: $message"
}

resolve_alert() {
  local alert_type="$1"
  local task_id="$2"
  local resolved_by="${3:-monitor}"

  (
    flock -w 5 201 || return

    python3 -c "
import json, sys, os
from datetime import datetime, timezone

alerts_file = sys.argv[1]
alert_type = sys.argv[2]
task_id = sys.argv[3]
resolved_by = sys.argv[4]

try:
    with open(alerts_file) as f:
        data = json.load(f)
except:
    return

now = datetime.now(timezone.utc).isoformat()
changed = False
for a in data['alerts']:
    if (a.get('type') == alert_type and
        a.get('task_id') == task_id and
        a.get('resolved_at') is None):
        a['resolved_at'] = now
        a['resolved_by'] = resolved_by
        changed = True

if changed:
    with open(alerts_file + '.new', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    os.rename(alerts_file + '.new', alerts_file)
" "$ALERTS_FILE" "$alert_type" "$task_id" "$resolved_by"

  ) 201>"${STATE_DIR}/.alerts.lock"
}

# --- 1. OpenCode Server Health Check ---
check_opencode_health() {
  local failures
  failures=$(cat "$HEALTH_STATE_FILE" 2>/dev/null || echo "0")
  [[ "$failures" =~ ^[0-9]+$ ]] || failures=0

  if curl -sf --max-time 5 "${OPENCODE_URL}/session" >/dev/null 2>&1; then
    # Server is up
    if [ "$failures" -gt 0 ]; then
      log "OpenCode server recovered after $failures failures"
      echo "0" > "$HEALTH_STATE_FILE"
      # Resolve any server_down alerts
      resolve_alert "server_down" "global"
    fi
    return 0
  else
    # Server is down
    failures=$((failures + 1))
    echo "$failures" > "$HEALTH_STATE_FILE"
    log "OpenCode server unreachable (failure #$failures)"

    if [ "$failures" -ge 3 ]; then
      write_alert "server_down" "global" \
        "OpenCode server at ${OPENCODE_URL} unreachable for $failures consecutive checks" \
        "critical"

      # Pause all active tasks
      local active_tasks
      active_tasks=$(bash "$SCRIPT_DIR/task-manager.sh" list --active 2>/dev/null || echo "[]")
      echo "$active_tasks" | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
for t in tasks:
    if t.get('status') not in ('paused',):
        print(t['id'])
" 2>/dev/null | while read -r tid; do
        bash "$SCRIPT_DIR/task-manager.sh" status "$tid" "paused" >/dev/null 2>&1 || true
        log "Paused task $tid (server down)"
      done
    fi
    return 1
  fi
}

# --- 2-4. Task Checks (timeouts, idle, nudge, boulder cross-ref) ---
check_tasks() {
  local active_tasks
  active_tasks=$(bash "$SCRIPT_DIR/task-manager.sh" list --active 2>/dev/null || echo "[]")

  local task_count
  task_count=$(echo "$active_tasks" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

  if [ "$task_count" -eq 0 ]; then
    log "No active tasks"
    return 0
  fi

  log "Checking $task_count active task(s)..."

  echo "$active_tasks" | python3 -c "
import json, sys
from datetime import datetime, timezone

# Timeout constants passed via argv
PLANNING_MIN = int(sys.argv[1])
EXECUTION_MIN = int(sys.argv[2])
TOTAL_MIN = int(sys.argv[3])

tasks = json.load(sys.stdin)
now = datetime.now(timezone.utc)

for t in tasks:
    task_id = t.get('id', '?')
    status = t.get('status', '?')
    created_at = t.get('created_at', '')
    phase_started_at = t.get('phase_started_at', '')
    last_idle_at = t.get('last_idle_at', '')
    nudge_count = t.get('nudge_count', 0)
    session_id = t.get('session_id', '')
    workspace = t.get('workspace', '')

    def parse_time(ts):
        if not ts:
            return None
        try:
            return datetime.fromisoformat(ts.replace('Z', '+00:00'))
        except:
            return None

    created = parse_time(created_at)
    phase_started = parse_time(phase_started_at)

    # Calculate durations in minutes
    total_min = (now - created).total_seconds() / 60 if created else 0
    phase_min = (now - phase_started).total_seconds() / 60 if phase_started else 0

    actions = []

    # Total TTL check
    if total_min > TOTAL_MIN:
        actions.append(('timeout', 'critical', f'Total TTL exceeded ({total_min:.0f} min > {TOTAL_MIN} min)'))

    # Phase timeout
    elif status == 'planning' and phase_min > PLANNING_MIN:
        actions.append(('timeout', 'critical', f'Planning timeout ({phase_min:.0f} min > {PLANNING_MIN} min)'))

    elif status == 'executing' and phase_min > EXECUTION_MIN:
        actions.append(('timeout', 'critical', f'Execution timeout ({phase_min:.0f} min > {EXECUTION_MIN} min)'))

    # Output actions as JSON lines
    for action_type, severity, message in actions:
        print(json.dumps({
            'action': action_type,
            'task_id': task_id,
            'status': status,
            'severity': severity,
            'message': message,
            'session_id': session_id or '',
            'workspace': workspace or '',
            'nudge_count': nudge_count,
            'phase_min': round(phase_min, 1),
            'total_min': round(total_min, 1)
        }))

    # Idle check (only for planning/executing with a session)
    if status in ('planning', 'executing') and session_id and not actions:
        print(json.dumps({
            'action': 'idle_check',
            'task_id': task_id,
            'status': status,
            'session_id': session_id,
            'workspace': workspace or '',
            'nudge_count': nudge_count,
            'phase_min': round(phase_min, 1)
        }))

    # Boulder cross-reference (only for tasks with workspace)
    if status in ('planning', 'executing') and workspace:
        print(json.dumps({
            'action': 'boulder_check',
            'task_id': task_id,
            'status': status,
            'workspace': workspace
        }))
" "$DEFAULT_PLANNING_MIN" "$DEFAULT_EXECUTION_MIN" "$DEFAULT_TOTAL_MIN" 2>/dev/null | while IFS= read -r action_json; do
    local action task_id severity message session_id workspace nudge_count
    action=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['action'])" 2>/dev/null) || continue
    task_id=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['task_id'])" 2>/dev/null) || continue

    if [ -z "$action" ] || [ -z "$task_id" ]; then
      log "WARNING: Malformed action JSON, skipping"
      continue
    fi

    case "$action" in
      timeout)
        severity=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['severity'])" 2>/dev/null)
        message=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['message'])" 2>/dev/null)
        session_id=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

        # Abort the session if exists
        if [ -n "$session_id" ]; then
          bash "$SCRIPT_DIR/opencode-session.sh" abort "$session_id" >/dev/null 2>&1 || true
        fi

        # Mark task as timed_out
        bash "$SCRIPT_DIR/task-manager.sh" status "$task_id" "timed_out" >/dev/null 2>&1 || true
        bash "$SCRIPT_DIR/task-manager.sh" update "$task_id" "error" "$message" >/dev/null 2>&1 || true

        write_alert "timeout" "$task_id" "$message" "$severity"
        log "TIMEOUT: $task_id — $message"
        ;;

      idle_check)
        session_id=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])" 2>/dev/null)
        workspace=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace'])" 2>/dev/null)
        nudge_count=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['nudge_count'])" 2>/dev/null)

        # Check if session is idle (no recent activity)
        local session_status
        session_status=$(timeout 15 bash "$SCRIPT_DIR/opencode-session.sh" status "$session_id" 2>/dev/null || echo "{}")
        local is_busy
        is_busy=$(echo "$session_status" | python3 -c "
import sys, json
try:
    s = json.load(sys.stdin)
    # Session is busy if it has pending tool calls or is generating
    busy = s.get('busy', False)
    print('true' if busy else 'false')
except:
    print('unknown')
" 2>/dev/null)

        if [ "$is_busy" = "true" ]; then
          # Session is still working, not idle
          log "Task $task_id: session active (busy)"
          continue
        fi

        if [ "$is_busy" = "unknown" ]; then
          # Can't determine status, skip
          continue
        fi

        # Session is idle — check workspace for changes
        local has_changes="false"
        local has_commits="false"
        if [ -d "$workspace" ]; then
          local git_status
          git_status=$(cd "$workspace" && git status --porcelain 2>/dev/null || true)
          if [ -n "$git_status" ]; then
            has_changes="true"
          fi

          local unpushed
          unpushed=$(cd "$workspace" && git log --oneline "@{u}..HEAD" 2>/dev/null || true)
          if [ -n "$unpushed" ]; then
            has_commits="true"
          fi
        fi

        # Nudge logic
        if [ "$has_changes" = "true" ] && [ "$nudge_count" -lt 2 ]; then
          # Auto-nudge: uncommitted changes
          local nudge_msg="Your implementation looks complete. Please commit and push your changes."
          local nudge_file
          nudge_file=$(mktemp "/tmp/nudge-XXXXXX.txt")
          echo "$nudge_msg" > "$nudge_file"
          bash "$SCRIPT_DIR/opencode-session.sh" send "$session_id" "$nudge_file" >/dev/null 2>&1 || true
          rm -f "$nudge_file"

          local new_count=$((nudge_count + 1))
          bash "$SCRIPT_DIR/task-manager.sh" update "$task_id" "nudge_count" "$new_count" >/dev/null 2>&1 || true
          log "Nudged task $task_id ($new_count/2): uncommitted changes"

        elif [ "$has_commits" = "true" ] && [ "$nudge_count" -lt 2 ]; then
          # Auto-nudge: committed but not pushed
          local nudge_msg="Your commits are ready. Please push to origin."
          local nudge_file
          nudge_file=$(mktemp "/tmp/nudge-XXXXXX.txt")
          echo "$nudge_msg" > "$nudge_file"
          bash "$SCRIPT_DIR/opencode-session.sh" send "$session_id" "$nudge_file" >/dev/null 2>&1 || true
          rm -f "$nudge_file"

          local new_count=$((nudge_count + 1))
          bash "$SCRIPT_DIR/task-manager.sh" update "$task_id" "nudge_count" "$new_count" >/dev/null 2>&1 || true
          log "Nudged task $task_id ($new_count/2): unpushed commits"

        elif [ "$nudge_count" -ge 2 ]; then
          # 2 nudges sent, escalate to the orchestrator
          write_alert "idle_unresolved" "$task_id" \
            "Agent idle after 2 nudges. has_changes=$has_changes has_commits=$has_commits" \
            "medium"
          log "Escalated task $task_id: idle after 2 nudges"

        else
          # No changes at all — escalate
          write_alert "idle_unresolved" "$task_id" \
            "Agent idle with no workspace changes" \
            "medium"
          log "Escalated task $task_id: idle with no changes"
        fi
        ;;

      boulder_check)
        workspace=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace'])" 2>/dev/null)
        local status
        status=$(echo "$action_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null)

        local boulder_file="$workspace/.sisyphus/boulder.json"
        if [ -f "$boulder_file" ]; then
          local boulder_agent
          boulder_agent=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('agent', 'unknown'))
except:
    print('unknown')
" "$boulder_file" 2>/dev/null)

          # Expected agent based on task status
          local expected_agent="unknown"
          case "$status" in
            planning) expected_agent="prometheus" ;;
            executing) expected_agent="atlas" ;;
          esac

          if [ "$boulder_agent" != "unknown" ] && [ "$expected_agent" != "unknown" ] && \
             [ "$boulder_agent" != "$expected_agent" ]; then
            write_alert "agent_mismatch" "$task_id" \
              "boulder.json agent=$boulder_agent but expected $expected_agent (task status=$status)" \
              "critical"
            log "MISMATCH: task $task_id — boulder=$boulder_agent expected=$expected_agent"
          fi
        fi
        ;;
    esac
  done
}

# --- 5. Session Cleanup for Terminal Tasks ---
cleanup_sessions() {
  log "Checking for terminal tasks with active sessions..."
  bash "$SCRIPT_DIR/task-manager.sh" cleanup-all >/dev/null 2>&1 || true
}

# --- 6. Workspace Retention ---
cleanup_workspaces() {
  log "Checking workspace retention..."

  local terminal_tasks
  terminal_tasks=$(python3 -c "
import json, sys
from datetime import datetime, timezone

tasks_file = sys.argv[1]
retention_hours = int(sys.argv[2])

try:
    with open(tasks_file) as f:
        state = json.load(f)
except:
    sys.exit(0)

now = datetime.now(timezone.utc)
terminal = {'failed', 'aborted', 'timed_out'}

for task_id, task in state.get('tasks', {}).items():
    status = task.get('status', '')
    workspace = task.get('workspace', '')

    if status == 'completed':
        # Immediate cleanup
        if workspace:
            print(json.dumps({'task_id': task_id, 'workspace': workspace, 'reason': 'completed'}))

    elif status in terminal:
        updated = task.get('updated_at', '')
        if updated:
            try:
                updated_dt = datetime.fromisoformat(updated.replace('Z', '+00:00'))
                age_hours = (now - updated_dt).total_seconds() / 3600
                if age_hours > retention_hours:
                    print(json.dumps({'task_id': task_id, 'workspace': workspace, 'reason': f'{status} ({age_hours:.0f}h old)'}))
            except:
                pass
" "$TASKS_FILE" "$RETENTION_FAILED_HOURS" 2>/dev/null) || true

  if [ -z "$terminal_tasks" ]; then
    return 0
  fi

  echo "$terminal_tasks" | while IFS= read -r line; do
    local ws_task_id ws_path ws_reason
    ws_task_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['task_id'])" 2>/dev/null)
    ws_path=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace'])" 2>/dev/null)
    ws_reason=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['reason'])" 2>/dev/null)

    if [ -d "$ws_path" ]; then
      bash "$SCRIPT_DIR/cleanup-workspace.sh" "$ws_task_id" --delete-branch >/dev/null 2>&1 || true
      log "Cleaned workspace for $ws_task_id ($ws_reason)"
    fi
  done
}

# --- 7. Concurrency Queue Management ---
check_queue() {
  # Check if we can start pending tasks
  local active_count
  active_count=$(bash "$SCRIPT_DIR/task-manager.sh" list --active 2>/dev/null | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

  # Max concurrent tasks (hardcoded for now, repo config in 5B)
  local max_tasks=3

  if [ "$active_count" -ge "$max_tasks" ]; then
    return 0
  fi

  # Check queue
  local queue_size
  queue_size=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        state = json.load(f)
    queue = state.get('queue', [])
    print(len(queue))
except:
    print(0)
" "$TASKS_FILE" 2>/dev/null)

  if [ "$queue_size" -gt 0 ]; then
    log "Queue has $queue_size pending task(s), $active_count/$max_tasks active"
    write_alert "queue_ready" "global" \
      "Queue has $queue_size pending task(s) and $active_count/$max_tasks slots used" \
      "low"
  fi
}

# --- Summary ---
print_summary() {
  local active_count alert_count
  active_count=$(bash "$SCRIPT_DIR/task-manager.sh" list --active 2>/dev/null | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

  alert_count=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    unresolved = [a for a in data.get('alerts', []) if a.get('resolved_at') is None]
    print(len(unresolved))
except:
    print(0)
" "$ALERTS_FILE" 2>/dev/null)

  local health_failures
  health_failures=$(cat "$HEALTH_STATE_FILE" 2>/dev/null || echo "0")

  python3 -c "
import json, sys
print(json.dumps({
    'active_tasks': int(sys.argv[1]),
    'unresolved_alerts': int(sys.argv[2]),
    'opencode_health_failures': int(sys.argv[3]),
    'status': 'healthy' if int(sys.argv[2]) == 0 and int(sys.argv[3]) == 0 else 'attention_needed'
}, indent=2))
" "$active_count" "$alert_count" "$health_failures"
}

# --- Main ---
ensure_state

SUBCOMMAND="${1:-all}"

case "$SUBCOMMAND" in
  all)
    check_opencode_health || true
    check_tasks
    cleanup_sessions
    cleanup_workspaces
    check_queue
    print_summary
    ;;
  health)
    check_opencode_health
    print_summary
    ;;
  tasks)
    check_tasks
    print_summary
    ;;
  cleanup)
    cleanup_sessions
    cleanup_workspaces
    print_summary
    ;;
  *)
    log "Usage: monitor.sh [all|health|tasks|cleanup]"
    exit 1
    ;;
esac
