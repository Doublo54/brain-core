#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# audit-trail.sh — Structured audit trail for agent lifecycle events
#
# Provides accountability and traceability for all agent-related actions.
# Events are stored in JSONL format (one JSON object per line) for simplicity,
# append-only semantics, and easy grepping.
#
# Usage:
#   audit-trail.sh log <event-type> <agent-id> <description> [--actor <who>] [--details <json>]
#   audit-trail.sh query [--type <event-type>] [--agent <agent-id>] [--since <ISO-date>] [--limit <n>]
#   audit-trail.sh tail [--count <n>]
#
# Event types:
#   agent_created, agent_upgraded, agent_archived, config_changed,
#   external_message_sent, task_delegated, knowledge_written
#
# Event JSON structure:
#   {"timestamp": "ISO-8601", "event_type": "agent_created", "agent_id": "finance",
#    "actor": "admin", "description": "Created finance agent from role template",
#    "details": {}}
#
# Output (stdout): JSON or JSONL
# Logging (stderr): progress/errors
#
# Exit codes:
#   0 — Success
#   1 — Invalid arguments or usage error
#   2 — Audit file I/O error

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(pwd)}"
STATE_DIR="${WORKSPACE}/state"
AUDIT_FILE="${STATE_DIR}/audit.jsonl"

VALID_EVENT_TYPES="agent_created agent_upgraded agent_archived config_changed external_message_sent task_delegated knowledge_written"

# --- Logging ---
log() {
  echo "[audit-trail] $*" >&2
}

error() {
  echo "[audit-trail] ERROR: $*" >&2
}

# --- Ensure state directory exists ---
ensure_state_dir() {
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
    log "Created state directory: $STATE_DIR"
  fi
}

# --- Validate event type ---
validate_event_type() {
  local event_type="$1"
  if [[ ! " $VALID_EVENT_TYPES " =~ " $event_type " ]]; then
    error "Invalid event type: $event_type"
    error "Valid types: $VALID_EVENT_TYPES"
    return 1
  fi
}

# --- Log an audit event ---
# Usage: log_event <event-type> <agent-id> <description> [--actor <who>] [--details <json>]
log_event() {
  if [[ $# -lt 3 ]]; then
    error "Usage: audit-trail.sh log <event-type> <agent-id> <description> [--actor <who>] [--details <json>]"
    return 1
  fi

  local event_type="$1"
  local agent_id="$2"
  local description="$3"
  shift 3

  validate_event_type "$event_type" || return 1

  local actor="${USER:-system}"
  local details="{}"

  # Parse optional arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --actor)
        actor="$2"
        shift 2
        ;;
      --details)
        details="$2"
        shift 2
        ;;
      *)
        error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  ensure_state_dir

  # Generate ISO-8601 timestamp
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build event JSON using Python3 (matching task-manager.sh pattern)
  local event_json
  if ! event_json=$(python3 - "$timestamp" "$event_type" "$agent_id" "$actor" "$description" "$details" <<'PYEOF' 2>&1
import json
import sys

timestamp = sys.argv[1]
event_type = sys.argv[2]
agent_id = sys.argv[3]
actor = sys.argv[4]
description = sys.argv[5]
details_raw = sys.argv[6]

event = {
    'timestamp': timestamp,
    'event_type': event_type,
    'agent_id': agent_id,
    'actor': actor,
    'description': description,
    'details': json.loads(details_raw)
}

print(json.dumps(event, separators=(',', ':')))
PYEOF
); then
    error "Failed to generate event JSON: $event_json"
    return 2
  fi

  # Append to audit file with flock for safe concurrent writes
  (
    flock -x 200
    echo "$event_json" >> "$AUDIT_FILE"
  ) 200>"${AUDIT_FILE}.lock"

  if [[ $? -ne 0 ]]; then
    error "Failed to write to audit file: $AUDIT_FILE"
    return 2
  fi

  log "Logged event: $event_type for agent $agent_id"
  echo "$event_json"
}

# --- Query audit events ---
# Usage: query_events [--type <event-type>] [--agent <agent-id>] [--since <ISO-date>] [--limit <n>]
query_events() {
  local filter_type=""
  local filter_agent=""
  local filter_since=""
  local limit=""

  # Parse optional arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)
        filter_type="$2"
        validate_event_type "$filter_type" || return 1
        shift 2
        ;;
      --agent)
        filter_agent="$2"
        shift 2
        ;;
      --since)
        filter_since="$2"
        shift 2
        ;;
      --limit)
        limit="$2"
        shift 2
        ;;
      *)
        error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ ! -f "$AUDIT_FILE" ]]; then
    log "No audit file found: $AUDIT_FILE"
    echo "[]"
    return 0
  fi

  # Use Python3 to filter and format results
  python3 - "$AUDIT_FILE" "$filter_type" "$filter_agent" "$filter_since" "$limit" <<'PYEOF'
import json
import sys

audit_file = sys.argv[1]
filter_type = sys.argv[2]
filter_agent = sys.argv[3]
filter_since = sys.argv[4]
limit = sys.argv[5]

results = []
with open(audit_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)

            # Apply filters
            if filter_type and event.get('event_type') != filter_type:
                continue
            if filter_agent and event.get('agent_id') != filter_agent:
                continue
            if filter_since and event.get('timestamp', '') < filter_since:
                continue

            results.append(event)
        except json.JSONDecodeError:
            pass

# Apply limit if specified
if limit:
    results = results[-int(limit):]

print(json.dumps(results, indent=2))
PYEOF

  if [[ $? -ne 0 ]]; then
    error "Failed to query audit events"
    return 2
  fi
}

# --- Tail recent events ---
# Usage: tail_events [--count <n>]
tail_events() {
  local count=10

  # Parse optional arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --count)
        count="$2"
        shift 2
        ;;
      *)
        error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ ! -f "$AUDIT_FILE" ]]; then
    log "No audit file found: $AUDIT_FILE"
    echo "[]"
    return 0
  fi

  # Use Python3 to get last N events
  python3 - "$AUDIT_FILE" "$count" <<'PYEOF'
import json
import sys

audit_file = sys.argv[1]
count = int(sys.argv[2])

results = []
with open(audit_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
            results.append(event)
        except json.JSONDecodeError:
            pass

# Get last N events
results = results[-count:]

print(json.dumps(results, indent=2))
PYEOF

  if [[ $? -ne 0 ]]; then
    error "Failed to tail audit events"
    return 2
  fi
}

# --- Main command dispatcher ---
main() {
  if [[ $# -lt 1 ]]; then
    error "Usage: audit-trail.sh <command> [args...]"
    error "Commands: log, query, tail"
    return 1
  fi

  local command="$1"
  shift

  case "$command" in
    log)
      log_event "$@"
      ;;
    query)
      query_events "$@"
      ;;
    tail)
      tail_events "$@"
      ;;
    *)
      error "Unknown command: $command"
      error "Valid commands: log, query, tail"
      return 1
      ;;
  esac
}

main "$@"
