#!/usr/bin/env bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# opencode-orphan-cleanup.sh — Delete OpenCode sessions whose parent no longer exists
#
# Usage: opencode-orphan-cleanup.sh [--dry-run]
#   --dry-run: List orphans without deleting
#
# Exit codes:
#   0 — Success (or no orphans found)
#   1 — Invalid arguments or missing dependencies
#   2 — Server connection error
#   3 — API error (invalid response or HTTP error)
#   4 — Partial failure (some deletions failed)

set -euo pipefail

OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:4096}"
DRY_RUN=false

# Validate URL format and normalize
[[ "$OPENCODE_URL" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?$ ]] || {
  echo "ERROR: Invalid OPENCODE_URL format: ${OPENCODE_URL}" >&2
  exit 1
}
OPENCODE_URL="${OPENCODE_URL%/}"

# Validate argument count and parse
if (( "$#" > 1 )); then
  echo "ERROR: Too many arguments" >&2
  echo "Usage: ${0##*/} [--dry-run]" >&2
  exit 1
elif (( "$#" == 1 )); then
  if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE — listing orphans without deleting"
  else
    echo "ERROR: Unknown argument: $1" >&2
    echo "Usage: ${0##*/} [--dry-run]" >&2
    exit 1
  fi
fi

# Ensure python3 is available
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required but not found" >&2
  exit 1
}

echo "Scanning for orphaned sessions..."

# Secure temp file with cleanup trap
ORPHAN_TMP=$(mktemp "${TMPDIR:-/tmp}/orphan_cleanup.XXXXXX") || {
  echo "ERROR: Cannot create temp file" >&2
  exit 3
}
trap 'rm -f "$ORPHAN_TMP"' EXIT INT TERM

# Fetch all sessions with HTTP status check
RESPONSE=$(curl -s --max-time 30 -w '\n%{http_code}' "${OPENCODE_URL}/session" 2>/dev/null) || {
  echo "ERROR: Cannot connect to OpenCode server at ${OPENCODE_URL}" >&2
  exit 2
}

# Extract HTTP status and body
HTTP_STATUS=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
SESSIONS_JSON=$(echo "$RESPONSE" | sed '$d')

# Validate HTTP status (require 2xx)
if [[ ! "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
  echo "ERROR: OpenCode API returned HTTP status ${HTTP_STATUS}" >&2
  exit 3
fi

# Check if response is valid JSON array
if ! python3 -c "import json,sys; data=json.load(sys.stdin); sys.exit(0 if isinstance(data,list) else 1)" <<< "$SESSIONS_JSON" 2>/dev/null; then
  echo "ERROR: Invalid response from OpenCode server (expected JSON array)" >&2
  exit 3
fi

# Build set of all session IDs and find orphans
python3 -c "
import json, sys
try:
    sessions = json.load(sys.stdin)
    if not isinstance(sessions, list):
        sys.exit(1)
    all_ids = {s.get('id') for s in sessions if s.get('id')}
    for s in sessions:
        sid = s.get('id')
        parent_id = s.get('parentID')
        if parent_id and parent_id not in all_ids:
            title = s.get('title', 'untitled').replace('|', ' ')
            print(f'{sid}|{parent_id}|{title}')
except Exception as e:
    sys.stderr.write(f'WARNING: Failed to parse sessions: {e}\n')
    sys.exit(1)
" <<< "$SESSIONS_JSON" > "$ORPHAN_TMP" || {
  echo "ERROR: Failed to process sessions" >&2
  exit 3
}

ORPHAN_COUNT=$(wc -l < "$ORPHAN_TMP" | tr -d ' ')

if [[ "$ORPHAN_COUNT" -eq 0 ]]; then
  echo "No orphaned sessions found."
  exit 0
fi

echo "Found ${ORPHAN_COUNT} orphaned session(s):"

DELETED=0
FAILED=0

while IFS='|' read -r sid parent_id title; do
  # Validate session ID format (match opencode-session.sh pattern)
  if ! [[ "$sid" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    printf '  WARNING: Skipping invalid session ID: %s\n' "$sid" >&2
    continue
  fi
  
  printf '  %s (parent: %s, title: %s) ' "$sid" "$parent_id" "$title"
  
  if [[ "$DRY_RUN" == true ]]; then
    echo "[WOULD DELETE]"
    continue
  fi
  
  # Capture HTTP status for DELETE request
  DEL_RESPONSE=$(curl -s --max-time 30 -w '\n%{http_code}' -X DELETE "${OPENCODE_URL}/session/${sid}" 2>/dev/null)
  DEL_STATUS=$(echo "$DEL_RESPONSE" | tail -c 4 | tr -d '\n')
  
  if [[ "$DEL_STATUS" =~ ^2[0-9][0-9]$ ]]; then
    echo "DELETED"
    DELETED=$((DELETED + 1))
  else
    echo "FAILED (HTTP ${DEL_STATUS})"
    FAILED=$((FAILED + 1))
  fi
done < "$ORPHAN_TMP"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete. Use without --dry-run to delete."
  exit 0
fi

echo "Done. Deleted: ${DELETED}, Failed: ${FAILED}"
if [[ "$FAILED" -gt 0 ]]; then
  exit 4
fi
exit 0
