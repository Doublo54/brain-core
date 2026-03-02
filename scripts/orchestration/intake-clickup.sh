#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_MANAGER="${SCRIPT_DIR}/task-manager.sh"

CLICKUP_API_KEY="${CLICKUP_API_KEY:-}"
CLICKUP_LIST_ID="${CLICKUP_LIST_ID:-}"
CLICKUP_API_BASE="https://api.clickup.com/api/v2"
CLICKUP_TAG="${CLICKUP_TAG:-ai-task}"
INTAKE_STATE_DIR="${WORKSPACE:-$(pwd)}/state"
INTAKE_SEEN_FILE="${INTAKE_STATE_DIR}/.clickup-seen"

log() {
  echo "[intake-clickup] $*" >&2
}

if [ -z "$CLICKUP_API_KEY" ]; then
  log "CLICKUP_API_KEY not set — skipping ClickUp intake"
  exit 0
fi

if [ -z "$CLICKUP_LIST_ID" ]; then
  log "CLICKUP_LIST_ID not set — skipping ClickUp intake"
  exit 0
fi

mkdir -p "$INTAKE_STATE_DIR"
touch "$INTAKE_SEEN_FILE"

clickup_api() {
  local endpoint="$1"
  shift
  curl -s --max-time 30 \
    -H "Authorization: ${CLICKUP_API_KEY}" \
    -H "Content-Type: application/json" \
    "$@" \
    "${CLICKUP_API_BASE}${endpoint}"
}

log "Polling ClickUp list ${CLICKUP_LIST_ID} for tasks tagged '${CLICKUP_TAG}'..."

response=$(clickup_api "/list/${CLICKUP_LIST_ID}/task?tags[]=${CLICKUP_TAG}&include_closed=false" 2>/dev/null) || {
  log "ERROR: Failed to fetch ClickUp tasks"
  exit 1
}

task_data=$(echo "$response" | python3 -c "
import json, sys, hashlib, os

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

tasks = data.get('tasks', [])
for t in tasks:
    clickup_id = t.get('id', '')
    name = t.get('name', 'Untitled')
    description = t.get('description', '') or t.get('text_content', '') or name
    repo = ''
    for field in t.get('custom_fields', []):
        if field.get('name', '').lower() in ('repo', 'repository', 'github_repo'):
            repo = field.get('value', '') or ''
            break
    if not repo:
        repo = os.environ.get('CLICKUP_DEFAULT_REPO', 'owner/repo')

    hex_suffix = hashlib.md5(clickup_id.encode()).hexdigest()[:8]
    print(json.dumps({
        'clickup_id': clickup_id,
        'name': name,
        'description': description[:2000],
        'repo': repo,
        'hex': hex_suffix
    }))
" 2>/dev/null) || true

if [ -z "$task_data" ]; then
  log "No qualifying tasks found"
  exit 0
fi

created=0
skipped=0

while IFS= read -r line; do
  clickup_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['clickup_id'])")
  name=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  description=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['description'])")
  repo=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['repo'])")
  hex=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['hex'])")

  if grep -qF "$clickup_id" "$INTAKE_SEEN_FILE" 2>/dev/null; then
    skipped=$((skipped + 1))
    continue
  fi

  timestamp=$(date +%s)
  task_id="task-${timestamp}-${hex}"

  full_desc="[ClickUp #${clickup_id}] ${name}: ${description}"

  if "${TASK_MANAGER}" create "$task_id" "$repo" "$full_desc" --requested-by "clickup" > /dev/null 2>&1; then
    echo "$clickup_id" >> "$INTAKE_SEEN_FILE"
    log "Created task ${task_id} from ClickUp #${clickup_id}: ${name}"
    created=$((created + 1))

    clickup_api "/task/${clickup_id}/comment" \
      -X POST \
      -d "{\"comment_text\": \"Picked up by orchestrator as ${task_id}\"}" \
      > /dev/null 2>&1 || true
  else
    log "WARNING: Failed to create task from ClickUp #${clickup_id}"
  fi

  sleep 1
done <<< "$task_data"

log "Intake complete: created=${created} skipped=${skipped}"
echo "{\"created\": ${created}, \"skipped\": ${skipped}}"
