#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# opencode-session.sh — OpenCode HTTP API wrapper for the orchestrator
#
# Wraps common OpenCode session operations for programmatic use.
#
# Usage:
#   opencode-session.sh create
#   opencode-session.sh send <session-id> <message-file | -> [--agent <agent-name>]
#   opencode-session.sh status <session-id>
#   opencode-session.sh list
#   opencode-session.sh abort <session-id>
#   opencode-session.sh delete <session-id>
#
# Agent names (for --agent):
#   prometheus — planning only (writes to .sisyphus/plans/, no code)
#   atlas      — execution from plan (triggered by /start-work)
#   sisyphus   — general purpose (plans + codes, default)
#
# Output (stdout): JSON or session ID
# Logging (stderr): progress/errors
#
# Environment:
#   OPENCODE_URL — OpenCode server URL (default: http://127.0.0.1:4096)
#
# Exit codes:
#   0 — Success
#   1 — Invalid arguments or usage error
#   2 — Session not found
#   3 — Server connection error
#   4 — API error

set -euo pipefail

# --- Constants ---
OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:4096}"
CURL_TIMEOUT=30
SEND_TIMEOUT=120
SEND_MAX_RETRIES=3
SEND_BACKOFF=(5 10 20)

# --- Logging (all to stderr) ---
log() {
  echo "[opencode] $*" >&2
}

# --- Session ID validation (matches task-manager.sh pattern) ---
validate_session_id() {
  local sid="$1"
  if ! [[ "$sid" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    log "ERROR: Invalid session-id '$sid'"
    exit 1
  fi
}

# --- HTTP helper ---
# Makes a curl request with standard headers and error handling.
# Usage: api_call <method> <endpoint> [body] [timeout]
# Returns: response body on stdout, exits non-zero on failure
api_call() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"
  local timeout="${4:-$CURL_TIMEOUT}"
  local url="${OPENCODE_URL}${endpoint}"

  local curl_args=(
    -s
    --max-time "$timeout"
    -X "$method"
    -H "Content-Type: application/json"
    -w "\n%{http_code}"
  )

  if [ -n "$body" ]; then
    curl_args+=(-d "$body")
  fi

  local response
  response=$(curl "${curl_args[@]}" "$url" 2>/dev/null) || {
    log "ERROR: Cannot connect to OpenCode server at $OPENCODE_URL"
    log "Is the OpenCode server running? Check: curl -s ${OPENCODE_URL}/session"
    exit 3
  }

  # Split response body and HTTP status code
  # HTTP code is always the last line (from -w "\n%{http_code}")
  local http_code
  http_code="${response##*$'\n'}"
  local body_response
  if [[ "$response" == *$'\n'* ]]; then
    body_response="${response%$'\n'*}"
  else
    body_response=""
  fi

  # Validate we got a numeric HTTP code
  if ! [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
    log "ERROR: Unexpected response from $method $endpoint (no HTTP status code)"
    exit 4
  fi

  # Check HTTP status
  case "$http_code" in
    2[0-9][0-9])
      # 2xx — success
      echo "$body_response"
      ;;
    404)
      log "ERROR: Not found (404) — $method $endpoint"
      exit 2
      ;;
    *)
      log "ERROR: API returned HTTP $http_code — $method $endpoint"
      if [ -n "$body_response" ]; then
        log "Response: $body_response"
      fi
      exit 4
      ;;
  esac
}

# --- Subcommands ---

cmd_create() {
  log "Creating new session..."

  local response
  response=$(api_call POST "/session" '{}')

  # Extract session ID from response
  local session_id
  session_id=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # Handle both direct response and nested response
    if 'id' in data:
        print(data['id'])
    elif 'session' in data and 'id' in data['session']:
        print(data['session']['id'])
    else:
        print(json.dumps(data), file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'Failed to parse response: {e}', file=sys.stderr)
    sys.exit(1)
") || {
    log "ERROR: Failed to parse session creation response"
    log "Raw response: $response"
    exit 4
  }

  echo "$session_id"
  log "Created session: $session_id"
}

cmd_send() {
  if [ $# -lt 2 ]; then
    log "Usage: opencode-session.sh send <session-id> <message-file | -> [--agent <agent-name>] [--workspace <path>]"
    exit 1
  fi

  local session_id="$1"
  local message_source="$2"
  shift 2

  # Parse optional flags
  local agent_name=""
  local workspace_path=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent)
        if [ $# -lt 2 ]; then
          log "ERROR: --agent requires a value (prometheus, atlas, sisyphus)"
          exit 1
        fi
        agent_name="$2"
        shift 2
        ;;
      --workspace)
        if [ $# -lt 2 ]; then
          log "ERROR: --workspace requires a path"
          exit 1
        fi
        workspace_path="$2"
        shift 2
        ;;
      *)
        log "ERROR: Unknown flag '$1'"
        exit 1
        ;;
    esac
  done

  validate_session_id "$session_id"

  if [ "$message_source" != "-" ]; then
    local resolved
    resolved=$(realpath -m "$message_source" 2>/dev/null) || { log "ERROR: Cannot resolve path"; exit 1; }
    local allowed_base="${WORKSPACES_ROOT:-/opt/opencode}"
    if [[ "$resolved" != "${allowed_base}"/* && "$resolved" != /tmp/* ]]; then
      log "ERROR: Message file must be under $allowed_base or /tmp"
      exit 1
    fi
  fi

  local message
  if [ "$message_source" = "-" ]; then
    message=$(cat)
  elif [ -f "$message_source" ]; then
    message=$(cat "$message_source")
  else
    log "ERROR: Message source '$message_source' is not a file and not '-' (stdin)"
    exit 1
  fi

  if [ -z "$message" ]; then
    log "ERROR: Empty message"
    exit 1
  fi

  # Inject workspace context if --workspace was specified
  # This tells the agent which directory to work in (OpenCode sessions share a project root)
  # IMPORTANT: For slash commands (messages starting with /), APPEND context after the command
  # to avoid blocking OHO's auto-slash-command detection which checks message prefix
  if [ -n "$workspace_path" ]; then
    local ws_context="
<workspace-context>
WORKSPACE: ${workspace_path}
All file operations MUST happen inside this directory. Use absolute paths.
When running shell commands, always \`cd ${workspace_path}\` first.
Do NOT work in /opt/opencode/repos/ — that is the base clone, not the task workspace.
</workspace-context>"
    if [[ "$message" == /* ]]; then
      # Slash command — append after (preserves /command detection)
      message="${message}${ws_context}"
    else
      # Regular message — prepend before
      message="${ws_context}

${message}"
    fi
    log "Injected workspace context: $workspace_path"
  fi

  # Build JSON payload with proper escaping via python3
  # Includes agent field if --agent was specified
  local payload
  payload=$(printf '%s' "$message" | python3 -c "
import json, sys
message = sys.stdin.read()
agent = sys.argv[1]
payload = {
    'parts': [
        {
            'type': 'text',
            'text': message
        }
    ]
}
if agent:
    payload['agent'] = agent
print(json.dumps(payload))
" "$agent_name")

  # Retry loop with backoff — send is the critical path for orchestration
  local attempt=0
  local response=""
  local last_exit=0

  while [ "$attempt" -lt "$SEND_MAX_RETRIES" ]; do
    attempt=$((attempt + 1))
    log "Sending message to session $session_id (attempt $attempt/$SEND_MAX_RETRIES, timeout ${SEND_TIMEOUT}s)..."

    last_exit=0
    response=$(api_call POST "/session/${session_id}/message" "$payload" "$SEND_TIMEOUT") || last_exit=$?

    if [ "$last_exit" -eq 0 ]; then
      echo "$response"
      log "Message sent to session $session_id (attempt $attempt)"
      return 0
    fi

    # Don't retry on client errors (bad session id, not found, etc.)
    if [ "$last_exit" -eq 1 ] || [ "$last_exit" -eq 2 ]; then
      log "ERROR: Non-retryable error (exit $last_exit) on attempt $attempt"
      exit "$last_exit"
    fi

    # Retryable errors: connection (3) or server error (4)
    if [ "$attempt" -lt "$SEND_MAX_RETRIES" ]; then
      local delay="${SEND_BACKOFF[$((attempt - 1))]}"
      log "WARN: Send failed (exit $last_exit), retrying in ${delay}s..."
      sleep "$delay"
    fi
  done

  log "ERROR: Send failed after $SEND_MAX_RETRIES attempts (last exit: $last_exit)"
  exit "$last_exit"
}

cmd_status() {
  if [ $# -lt 1 ]; then
    log "Usage: opencode-session.sh status <session-id>"
    exit 1
  fi

  local session_id="$1"

  validate_session_id "$session_id"

  # Get all sessions and find the one we want
  local response
  response=$(api_call GET "/session")

  echo "$response" | python3 -c "
import json, sys

session_id = sys.argv[1]
try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError) as e:
    print(json.dumps({'error': f'Failed to parse server response: {e}'}), file=sys.stderr)
    sys.exit(4)

# Handle both array and {sessions: [...]} response shapes
sessions = data if isinstance(data, list) else (data.get('sessions') or [])

for s in sessions:
    if s.get('id') == session_id:
        # Determine busy status from session data
        # OpenCode sessions have various indicators — check for active message processing
        busy = s.get('busy', False)

        result = {
            'id': s.get('id'),
            'busy': busy,
            'title': s.get('title', ''),
        }
        print(json.dumps(result, indent=2))
        sys.exit(0)

print(json.dumps({'error': f'Session {session_id} not found'}), file=sys.stderr)
sys.exit(2)
" "$session_id" || {
    log "ERROR: Session '$session_id' not found"
    exit 2
  }
}

cmd_list() {
  local response
  response=$(api_call GET "/session")

  # Normalize response to array format
  echo "$response" | python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError) as e:
    print(json.dumps({'error': f'Failed to parse server response: {e}'}), file=sys.stderr)
    sys.exit(4)

# Handle both array and {sessions: [...]} response shapes
sessions = data if isinstance(data, list) else (data.get('sessions') or [])

# Output summary for each session
result = []
for s in sessions:
    result.append({
        'id': s.get('id'),
        'title': s.get('title', ''),
        'busy': s.get('busy', False),
    })

print(json.dumps(result, indent=2))
"
}

cmd_abort() {
  if [ $# -lt 1 ]; then
    log "Usage: opencode-session.sh abort <session-id>"
    exit 1
  fi

  local session_id="$1"

  validate_session_id "$session_id"

  log "Aborting session $session_id..."

  local response
  response=$(api_call POST "/session/${session_id}/abort")

  echo "$response"
  log "Aborted session $session_id"
}

cmd_delete() {
  if [ $# -lt 1 ]; then
    log "Usage: opencode-session.sh delete <session-id>"
    exit 1
  fi

  local session_id="$1"

  validate_session_id "$session_id"

  log "Deleting session $session_id..."

  local response
  response=$(api_call DELETE "/session/${session_id}")

  echo "$response"
  log "Deleted session $session_id"
}

# --- Main dispatch ---
if [ $# -lt 1 ]; then
  log "Usage: opencode-session.sh <command> [args...]"
  log "Commands: create, send, status, list, abort, delete"
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  create)  cmd_create "$@" ;;
  send)    cmd_send "$@" ;;
  status)  cmd_status "$@" ;;
  list)    cmd_list "$@" ;;
  abort)   cmd_abort "$@" ;;
  delete)  cmd_delete "$@" ;;
  *)
    log "ERROR: Unknown command '$COMMAND'. Valid: create, send, status, list, abort, delete"
    exit 1
    ;;
esac
