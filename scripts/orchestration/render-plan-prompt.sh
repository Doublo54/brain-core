#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# render-plan-prompt.sh — Render planning prompt template with task context
#
# Usage:
#   render-plan-prompt.sh TASK_ID OUTPUT_FILE [TEMPLATE_FILE]
#
# Reads task state, renders template with variables, writes to OUTPUT_FILE
# If TEMPLATE_FILE is not provided, uses templates/plan-prompt.md
#
# Variables replaced:
#   {{TASK_ID}}          → task ID
#   {{TASK_DESCRIPTION}} → task description
#   {{REPO_NAME}}        → repo name (e.g., "example-monorepo")
#   {{BASE_BRANCH}}      → base branch (e.g., "main")
#   {{WORKSPACE}}        → workspace absolute path
#
# Exit codes:
#   0 — Success
#   1 — Invalid arguments
#   2 — Task not found
#   3 — Template not found
#   4 — Validation failed (missing critical sections)
#   5 — JSON parse error or missing required fields

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
DEFAULT_TEMPLATE="${WORKSPACE}/config/templates/plan-prompt.md"

log() {
  echo "[render] $*" >&2
}

if [ $# -lt 2 ]; then
  log "Usage: render-plan-prompt.sh TASK_ID OUTPUT_FILE [TEMPLATE_FILE]"
  exit 1
fi

TASK_ID="$1"
OUTPUT_FILE="$2"
TEMPLATE_FILE="${3:-$DEFAULT_TEMPLATE}"

# Use mktemp for atomic write (safer than .tmp.$$)
TEMP_OUTPUT=$(mktemp "${OUTPUT_FILE}.XXXXXX")

# Cleanup on exit
cleanup() {
  rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT

# Validate template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
  log "ERROR: Template not found: $TEMPLATE_FILE"
  exit 3
fi

# Get task state (stderr flows to terminal, not captured into JSON)
TASK_JSON=$(bash "$SCRIPT_DIR/task-manager.sh" get "$TASK_ID") || {
  EXIT_CODE=$?
  case $EXIT_CODE in
    2) log "ERROR: Task '$TASK_ID' not found" ;;
    *) log "ERROR: Failed to get task '$TASK_ID' (exit code: $EXIT_CODE)" ;;
  esac
  exit $EXIT_CODE
}

# Extract all task fields in a single python3 call (validates JSON + required keys)
FIELDS=$(echo "$TASK_JSON" | python3 -c "
import sys, json
from urllib.parse import urlparse

try:
    d = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f'ERROR: Invalid JSON from task-manager.sh: {e}', file=sys.stderr)
    sys.exit(5)

required = ['description', 'repo_url', 'base_branch', 'workspace']
missing = [k for k in required if k not in d]
if missing:
    print(f'ERROR: Missing required fields: {missing}', file=sys.stderr)
    sys.exit(5)

repo_url = d['repo_url']
path = urlparse(repo_url).path.rstrip('/').split('/')
repo_name = path[-1] if path and path[-1] else repo_url

# Output as tab-separated (safe: fields shouldn't contain tabs)
print(f\"{d['description']}\t{repo_name}\t{d['base_branch']}\t{d['workspace']}\")
") || {
  log "ERROR: Failed to extract fields from task JSON"
  exit 5
}

# Parse tab-separated fields
IFS=$'\t' read -r TASK_DESCRIPTION REPO_NAME BASE_BRANCH WORKSPACE <<< "$FIELDS"

log "Rendering template for task $TASK_ID"
log "  Description: ${TASK_DESCRIPTION:0:60}..."
log "  Repo: $REPO_NAME"
log "  Base branch: $BASE_BRANCH"
log "  Workspace: $WORKSPACE"

# Read template and perform substitutions (write to temp file)
python3 - "$TEMPLATE_FILE" "$TASK_ID" "$TASK_DESCRIPTION" "$REPO_NAME" "$BASE_BRANCH" "$WORKSPACE" > "$TEMP_OUTPUT" <<'PYEOF'
import sys

template_path = sys.argv[1]
task_id = sys.argv[2]
task_description = sys.argv[3]
repo_name = sys.argv[4]
base_branch = sys.argv[5]
workspace = sys.argv[6]

with open(template_path) as f:
    template = f.read()

# Perform substitutions
result = template.replace('{{TASK_ID}}', task_id)
result = result.replace('{{TASK_DESCRIPTION}}', task_description)
result = result.replace('{{REPO_NAME}}', repo_name)
result = result.replace('{{BASE_BRANCH}}', base_branch)
result = result.replace('{{WORKSPACE}}', workspace)

print(result, end='')
PYEOF

if [ ! -f "$TEMP_OUTPUT" ]; then
  log "ERROR: Template rendering failed (no output generated)"
  exit 4
fi

# Get file size
FILE_SIZE=$(wc -c < "$TEMP_OUTPUT")
log "Size: $FILE_SIZE bytes"

# Sanity check: warn if suspiciously large
if [ "$FILE_SIZE" -gt 51200 ]; then
  log "WARNING: Rendered prompt is unusually large ($FILE_SIZE bytes > 50KB)"
  log "Check task description for unexpected content"
fi

# Validate critical sections exist (fail-fast)
VALIDATION_FAILED=0

if ! grep -q "## Communication" "$TEMP_OUTPUT"; then
  log "ERROR: Communication section not found in rendered prompt"
  VALIDATION_FAILED=1
fi

if ! grep -q "NEVER use the question tool" "$TEMP_OUTPUT"; then
  log "ERROR: Question tool prohibition not found in rendered prompt"
  VALIDATION_FAILED=1
fi

if ! grep -q "## Commit Rules" "$TEMP_OUTPUT"; then
  log "ERROR: Commit Rules section not found in rendered prompt"
  VALIDATION_FAILED=1
fi

if [ $VALIDATION_FAILED -eq 1 ]; then
  log "FATAL: Rendered prompt missing critical sections"
  log "Template may be corrupted or variables not properly substituted"
  exit 4
fi

log "Validation passed: all critical sections present"

# Move temp file to final location (atomic)
mv "$TEMP_OUTPUT" "$OUTPUT_FILE"
log "Rendered prompt written to: $OUTPUT_FILE"
