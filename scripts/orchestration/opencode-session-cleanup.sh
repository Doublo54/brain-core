#!/usr/bin/env bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# opencode-session-cleanup.sh — Clean up old OpenCode sessions by age
#
# Usage: opencode-session-cleanup.sh [max-age-hours]
#   max-age-hours: Delete sessions older than this (default: 48)
#
# Exit codes:
#   0 — Success (no sessions to clean, or all deletions succeeded)
#   1 — Invalid arguments or missing dependencies
#   2 — Server connection error
#   3 — API error (invalid response or HTTP error)
#   4 — Partial failure (some deletions failed)

set -euo pipefail

# Validate argument count
if (($# > 1)); then
  echo "Usage: ${0##*/} [max-age-hours]" >&2
  echo "  max-age-hours: Delete sessions older than this (default: 48)" >&2
  exit 1
fi

OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:4096}"
MAX_AGE_HOURS="${1:-48}"

# Validate URL format and normalize (strip trailing slash)
[[ "$OPENCODE_URL" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?$ ]] || {
  echo "ERROR: Invalid OPENCODE_URL format: ${OPENCODE_URL}" >&2
  exit 1
}
OPENCODE_URL="${OPENCODE_URL%/}"

# Validate numeric input
if ! [[ "$MAX_AGE_HOURS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: max-age-hours must be a positive integer" >&2
  exit 1
fi

# Ensure python3 is available
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required but not found" >&2
  exit 1
}

MAX_AGE_MS=$((MAX_AGE_HOURS * 3600 * 1000))
NOW_MS=$(python3 -c "import time; print(int(time.time() * 1000))")
CUTOFF_MS=$((NOW_MS - MAX_AGE_MS))

# Format cutoff date for display using Python for portability
CUTOFF_DATE=$(python3 -c "import datetime; print(datetime.datetime.utcfromtimestamp($CUTOFF_MS / 1000).strftime('%Y-%m-%dT%H:%M:%SZ'))")
echo "Cleaning sessions older than ${MAX_AGE_HOURS}h (before ${CUTOFF_DATE})..."

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

# Find old sessions and delete them
DELETED=0
FAILED=0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  
  sid=$(echo "$line" | cut -d'|' -f1)
  updated=$(echo "$line" | cut -d'|' -f2)
  title=$(echo "$line" | cut -d'|' -f3-)
  
  # Validate session ID format (match opencode-session.sh pattern)
  if ! [[ "$sid" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "  WARNING: Skipping invalid session ID: ${sid}" >&2
    continue
  fi
  
  if [[ "$updated" =~ ^[0-9]+$ ]] && [[ "$updated" -lt "$CUTOFF_MS" ]]; then
    age_hours=$(( (NOW_MS - updated) / 3600000 ))
    printf '  Deleting: %s (age: %dh, title: %s)... ' "$sid" "$age_hours" "$title"
    
    # Capture HTTP status for DELETE request
    DEL_RESPONSE=$(curl -s --max-time 30 -w '\n%{http_code}' -X DELETE "${OPENCODE_URL}/session/${sid}" 2>/dev/null)
    DEL_STATUS=$(echo "$DEL_RESPONSE" | tail -c 4 | tr -d '\n')
    
    if [[ "$DEL_STATUS" =~ ^2[0-9][0-9]$ ]]; then
      echo "OK"
      DELETED=$((DELETED + 1))
    else
      echo "FAILED (HTTP ${DEL_STATUS})"
      FAILED=$((FAILED + 1))
    fi
  fi
done < <(python3 -c "
import json, sys
try:
    sessions = json.load(sys.stdin)
    if not isinstance(sessions, list):
        sys.exit(1)
    for s in sessions:
        sid = s.get('id', '')
        updated = s.get('time', {}).get('updated', 0)
        title = s.get('title', 'untitled').replace('|', ' ')
        print(f'{sid}|{updated}|{title}')
except Exception as e:
    sys.stderr.write(f'WARNING: Failed to parse sessions: {e}\n')
    sys.exit(1)
" <<< "$SESSIONS_JSON" || { echo "ERROR: Failed to process sessions" >&2; exit 3; })

echo "Done. Deleted: ${DELETED}, Failed: ${FAILED}"
if [[ "$FAILED" -gt 0 ]]; then
  exit 4
fi
exit 0
