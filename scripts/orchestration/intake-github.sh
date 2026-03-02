#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_MANAGER="${SCRIPT_DIR}/task-manager.sh"

GITHUB_LABEL="${GITHUB_LABEL:-ai-task}"
GITHUB_REPOS="${GITHUB_REPOS:-}"
INTAKE_STATE_DIR="${WORKSPACE:-$(pwd)}/state"
INTAKE_SEEN_FILE="${INTAKE_STATE_DIR}/.github-seen"

log() {
  echo "[intake-github] $*" >&2
}

if ! command -v gh &> /dev/null; then
  log "gh CLI not installed — skipping GitHub issue intake"
  exit 0
fi

if ! gh auth status &> /dev/null; then
  log "gh CLI not authenticated — skipping GitHub issue intake"
  exit 0
fi

if [ -z "$GITHUB_REPOS" ]; then
  log "GITHUB_REPOS not set — skipping GitHub issue intake (set as comma-separated list, e.g. 'owner/repo1,owner/repo2')"
  exit 0
fi

mkdir -p "$INTAKE_STATE_DIR"
touch "$INTAKE_SEEN_FILE"

created=0
skipped=0

IFS=',' read -ra repos <<< "$GITHUB_REPOS"

for repo in "${repos[@]}"; do
  repo=$(echo "$repo" | xargs)

  log "Checking ${repo} for issues labeled '${GITHUB_LABEL}'..."

  issues=$(gh issue list --repo "$repo" --label "$GITHUB_LABEL" --state open --json number,title,body --limit 50 2>/dev/null) || {
    log "WARNING: Failed to fetch issues from ${repo}"
    continue
  }

  issue_count=$(echo "$issues" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null) || continue

  if [ "$issue_count" = "0" ]; then
    continue
  fi

  while IFS= read -r line; do
    number=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['number'])")
    title=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")
    body=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('body','')[:1500])")

    issue_key="${repo}#${number}"

    if grep -qF "$issue_key" "$INTAKE_SEEN_FILE" 2>/dev/null; then
      skipped=$((skipped + 1))
      continue
    fi

    timestamp=$(date +%s)
    hex=$(printf '%s' "$issue_key" | md5sum 2>/dev/null | cut -c1-8 || printf '%s' "$issue_key" | md5 -q 2>/dev/null | cut -c1-8 || echo "00000000")
    task_id="task-${timestamp}-${hex}"

    full_desc="[GitHub ${issue_key}] ${title}: ${body}"

    if "${TASK_MANAGER}" create "$task_id" "$repo" "$full_desc" --requested-by "github-issue" > /dev/null 2>&1; then
      echo "$issue_key" >> "$INTAKE_SEEN_FILE"
      log "Created task ${task_id} from ${issue_key}: ${title}"
      created=$((created + 1))

      gh issue comment "$number" --repo "$repo" \
        --body "Picked up by orchestrator as \`${task_id}\`. Work will begin shortly." \
        2>/dev/null || log "WARNING: Failed to comment on ${issue_key}"
    else
      log "WARNING: Failed to create task from ${issue_key}"
    fi

    sleep 1
  done < <(echo "$issues" | python3 -c "
import json, sys
for issue in json.load(sys.stdin):
    print(json.dumps(issue))
" 2>/dev/null)
done

log "Intake complete: created=${created} skipped=${skipped}"
echo "{\"created\": ${created}, \"skipped\": ${skipped}}"
