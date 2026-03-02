#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# github-pr.sh — GitHub PR operations for the orchestrator
#
# Creates draft PRs from agent branches, checks approval status,
# posts comments, and undrafts PRs. Uses GitHub REST API directly.
#
# Usage:
#   github-pr.sh create <task-id>
#   github-pr.sh check <task-id>
#   github-pr.sh comment <task-id> <message>
#   github-pr.sh ready <task-id>
#
# Subcommands:
#   create   — Push branch + create draft PR + update task state (pr_number, pr_url)
#   check    — Check PR review status (APPROVED, CHANGES_REQUESTED, PENDING, COMMENTED)
#   comment  — Post a comment on the task's PR
#   ready    — Undraft PR (mark as ready for review)
#
# Output (stdout): JSON
# Logging (stderr): progress/errors
#
# Exit codes:
#   0 — Success
#   1 — Invalid arguments or usage error
#   2 — Task not found or missing required fields
#   3 — GitHub API error
#   4 — Git operation failed
#   5 — Task in wrong state for operation

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_API="https://api.github.com"
AGENT_ID="${AGENT_ID:-default}"
[[ "$AGENT_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "[github-pr] ERROR: invalid AGENT_ID '${AGENT_ID}'" >&2; exit 1; }
SAFE_AGENT_ID="${AGENT_ID//[^A-Za-z0-9_]/_}"
TOKEN_VAR="GITHUB_TOKEN_${SAFE_AGENT_ID}"
GITHUB_TOKEN="${!TOKEN_VAR:-${GITHUB_TOKEN:-}}"

# --- Logging (all to stderr) ---
log() {
  echo "[github-pr] $*" >&2
}

# --- Validate prerequisites ---
check_token() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log "ERROR: missing GitHub token; expected ${TOKEN_VAR} or GITHUB_TOKEN"
    exit 1
  fi
}

# --- Helper: get task JSON from task-manager ---
get_task() {
  local task_id="$1"
  local task_json
  task_json=$(bash "$SCRIPT_DIR/task-manager.sh" get "$task_id" 2>/dev/null) || {
    log "ERROR: Task '$task_id' not found"
    exit 2
  }
  echo "$task_json"
}

# --- Helper: extract field from task JSON ---
task_field() {
  local json="$1"
  local field="$2"
  echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
val = data.get(sys.argv[1])
if val is None or val == 'None':
    print('')
else:
    print(val)
" "$field" 2>/dev/null
}

# --- Helper: validate PR number is numeric ---
validate_pr_number() {
  local pr_number="$1"
  local task_id="$2"
  if [ -z "$pr_number" ] || [ "$pr_number" = "None" ]; then
    log "ERROR: Task '$task_id' has no PR"
    exit 2
  fi
  if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
    log "ERROR: Invalid PR number '$pr_number' for task '$task_id'"
    exit 2
  fi
}

# --- Helper: GitHub API call ---
gh_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local args=(
    -s
    -w "\n%{http_code}"
    --max-time 30
    -H "Authorization: token $GITHUB_TOKEN"
    -H "Accept: application/vnd.github+json"
    -X "$method"
  )

  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" -d "$data")
  fi

  local response
  response=$(curl "${args[@]}" "${GITHUB_API}${endpoint}" 2>/dev/null) || {
    log "ERROR: curl failed for $method $endpoint"
    exit 3
  }

  # Split response body and HTTP status code
  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  # Check for HTTP errors
  case "$http_code" in
    2[0-9][0-9]) ;; # 2xx — success
    *)
      log "WARNING: $method $endpoint returned HTTP $http_code"
      ;;
  esac

  echo "$body"
  return 0
}

# --- Subcommands ---

cmd_create() {
  if [ $# -lt 1 ]; then
    log "Usage: github-pr.sh create <task-id>"
    exit 1
  fi

  local task_id="$1"
  check_token

  # Get task state
  local task_json
  task_json=$(get_task "$task_id")

  local status branch base_branch repo workspace description pr_number
  status=$(task_field "$task_json" "status")
  branch=$(task_field "$task_json" "branch")
  base_branch=$(task_field "$task_json" "base_branch")
  repo=$(task_field "$task_json" "repo")
  workspace=$(task_field "$task_json" "workspace")
  description=$(task_field "$task_json" "description")
  pr_number=$(task_field "$task_json" "pr_number")

  # Validate required fields
  if [ -z "$branch" ] || [ -z "$base_branch" ] || [ -z "$repo" ] || [ -z "$workspace" ]; then
    log "ERROR: Task '$task_id' missing required fields (branch, base_branch, repo, workspace)"
    exit 2
  fi

  # Don't create if PR already exists
  if [ -n "$pr_number" ] && [ "$pr_number" != "None" ]; then
    log "ERROR: Task '$task_id' already has PR #$pr_number"
    exit 5
  fi

  # Validate workspace exists
  if [ ! -d "$workspace" ]; then
    log "ERROR: Workspace not found: $workspace"
    exit 4
  fi

  # Validate branch name (defense in depth — task-manager already validates task-id)
  if ! [[ "$branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$ ]]; then
    log "ERROR: Invalid branch name: $branch"
    exit 2
  fi

  # 1. Push branch to origin
  log "Pushing branch $branch to origin..."
  (cd "$workspace" && git push origin "$branch" 2>&1) || {
    log "ERROR: git push failed for branch $branch"
    exit 4
  }
  log "Branch pushed: $branch"

  # 2. Read plan content from .sisyphus/plans/ if available
  local plan_content=""
  local plan_dir="$workspace/.sisyphus/plans"
  if [ -d "$plan_dir" ]; then
    # Read first .md file found in plans directory
    local plan_file
    # Select newest plan file by modification time (handles multiple plan iterations)
    plan_file=$(find "$plan_dir" -maxdepth 2 -name "*.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    if [ -n "$plan_file" ]; then
      plan_content=$(head -c 50000 "$plan_file" 2>/dev/null || true)
      log "Read plan from: $plan_file ($(echo "$plan_content" | wc -c) bytes)"
    fi
  fi

  # 3. Build PR body
  local pr_body
  pr_body=$(python3 -c "
import json, sys

description = sys.argv[1]
task_id = sys.argv[2]
plan_content = sys.argv[3] if len(sys.argv) > 3 else ''

body_parts = []

if plan_content:
    body_parts.append('## Plan\n\n' + plan_content)
else:
    body_parts.append('## Task\n\n' + description)

body_parts.append('---')
body_parts.append(f'**Task ID:** \`{task_id}\`')
body_parts.append('')
body_parts.append('Approve this PR to start implementation.')

body = '\n\n'.join(body_parts)

# Truncate to GitHub's limit (~65535 chars for PR body)
if len(body) > 60000:
    body = body[:60000] + '\n\n...(truncated)'

print(body)
" "$description" "$task_id" "$plan_content" 2>/dev/null)

  # 4. Create draft PR via GitHub API
  local pr_title="[AI] ${task_id}: ${description}"
  # Truncate title to 256 chars (GitHub limit)
  if [ ${#pr_title} -gt 256 ]; then
    pr_title="${pr_title:0:253}..."
  fi

  local pr_data
  pr_data=$(python3 -c "
import json, sys

title = sys.argv[1]
head = sys.argv[2]
base = sys.argv[3]
body = sys.argv[4]

print(json.dumps({
    'title': title,
    'head': head,
    'base': base,
    'body': body,
    'draft': True
}))
" "$pr_title" "$branch" "$base_branch" "$pr_body" 2>/dev/null)

  log "Creating draft PR: $pr_title"

  local body
  body=$(gh_api "POST" "/repos/${repo}/pulls" "$pr_data")

  # Check for errors
  local created_pr_number created_pr_url
  created_pr_number=$(echo "$body" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'number' in data:
        print(data['number'])
    else:
        err = data.get('message', 'Unknown error')
        errors = data.get('errors', [])
        detail = '; '.join(e.get('message', '') for e in errors) if errors else ''
        print(f'ERROR:{err}' + (f' ({detail})' if detail else ''), file=sys.stderr)
        sys.exit(3)
except:
    print('ERROR:Failed to parse GitHub response', file=sys.stderr)
    sys.exit(3)
" 2>&1) || {
    log "ERROR: GitHub API returned: $(echo "$body" | head -5)"
    exit 3
  }

  # Check if we got an error prefix
  if [[ "$created_pr_number" == ERROR:* ]]; then
    log "ERROR: ${created_pr_number#ERROR:}"
    exit 3
  fi

  created_pr_url=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('html_url',''))" 2>/dev/null)

  log "Created draft PR #$created_pr_number: $created_pr_url"

  # 5. Update task state
  bash "$SCRIPT_DIR/task-manager.sh" update "$task_id" pr_number "$created_pr_number" >/dev/null 2>&1
  bash "$SCRIPT_DIR/task-manager.sh" update "$task_id" pr_url "$created_pr_url" >/dev/null 2>&1

  # Transition to plan_review if currently in planning
  local final_status="$status"
  if [ "$status" = "planning" ]; then
    bash "$SCRIPT_DIR/task-manager.sh" status "$task_id" plan_review >/dev/null 2>&1
    final_status="plan_review"
    log "Task status → plan_review"
  fi

  # Output result
  python3 -c "
import json, sys
print(json.dumps({
    'task_id': sys.argv[1],
    'pr_number': int(sys.argv[2]),
    'pr_url': sys.argv[3],
    'branch': sys.argv[4],
    'base_branch': sys.argv[5],
    'draft': True,
    'status': sys.argv[6]
}, indent=2))
" "$task_id" "$created_pr_number" "$created_pr_url" "$branch" "$base_branch" "$final_status"
}

cmd_check() {
  if [ $# -lt 1 ]; then
    log "Usage: github-pr.sh check <task-id>"
    exit 1
  fi

  local task_id="$1"
  check_token

  # Get task state
  local task_json
  task_json=$(get_task "$task_id")

  local repo pr_number
  repo=$(task_field "$task_json" "repo")
  pr_number=$(task_field "$task_json" "pr_number")

  validate_pr_number "$pr_number" "$task_id"

  # Fetch PR reviews
  log "Checking reviews for PR #$pr_number..."
  local reviews_json
  reviews_json=$(gh_api "GET" "/repos/${repo}/pulls/${pr_number}/reviews")

  # Determine latest review state per reviewer
  # GitHub reviews: APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, PENDING
  local result
  result=$(python3 -c "
import json, sys

reviews = json.load(sys.stdin)

if not isinstance(reviews, list):
    print(json.dumps({
        'status': 'ERROR',
        'message': reviews.get('message', 'Unknown error') if isinstance(reviews, dict) else 'Invalid response'
    }, indent=2))
    sys.exit(0)

# Get latest state per reviewer (reviews are ordered chronologically)
latest = {}
for r in reviews:
    user = r.get('user', {}).get('login', 'unknown')
    state = r.get('state', '')
    if state in ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED'):
        latest[user] = {
            'state': state,
            'submitted_at': r.get('submitted_at', ''),
            'body': (r.get('body') or '')[:500]
        }

# Determine overall status
# If ANY reviewer approved and NONE have changes_requested → APPROVED
# If ANY reviewer has changes_requested → CHANGES_REQUESTED
# If only comments → COMMENTED
# If no reviews → PENDING
states = [v['state'] for v in latest.values()]

if 'CHANGES_REQUESTED' in states:
    overall = 'CHANGES_REQUESTED'
elif 'APPROVED' in states:
    overall = 'APPROVED'
elif 'COMMENTED' in states:
    overall = 'COMMENTED'
else:
    overall = 'PENDING'

print(json.dumps({
    'status': overall,
    'pr_number': int(sys.argv[1]),
    'reviewers': latest,
    'review_count': len(reviews)
}, indent=2))
" "$pr_number" <<< "$reviews_json")

  echo "$result"

  local overall_status
  overall_status=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','PENDING'))" 2>/dev/null)
  log "PR #$pr_number review status: $overall_status"
}

cmd_comment() {
  if [ $# -lt 2 ]; then
    log "Usage: github-pr.sh comment <task-id> <message>"
    exit 1
  fi

  local task_id="$1"
  shift
  local message="$*"
  check_token

  # Get task state
  local task_json
  task_json=$(get_task "$task_id")

  local repo pr_number
  repo=$(task_field "$task_json" "repo")
  pr_number=$(task_field "$task_json" "pr_number")

  validate_pr_number "$pr_number" "$task_id"

  # Post comment via issues API (PRs are issues)
  local comment_data
  comment_data=$(python3 -c "
import json, sys
print(json.dumps({'body': sys.argv[1]}))
" "$message" 2>/dev/null)

  local response
  response=$(gh_api "POST" "/repos/${repo}/issues/${pr_number}/comments" "$comment_data")

  local comment_id comment_url
  comment_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  comment_url=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('html_url',''))" 2>/dev/null)

  if [ -z "$comment_id" ]; then
    log "ERROR: Failed to post comment"
    log "Response: $(echo "$response" | head -5)"
    exit 3
  fi

  log "Posted comment on PR #$pr_number: $comment_url"

  python3 -c "
import json, sys
print(json.dumps({
    'task_id': sys.argv[1],
    'pr_number': int(sys.argv[2]),
    'comment_id': int(sys.argv[3]),
    'comment_url': sys.argv[4]
}, indent=2))
" "$task_id" "$pr_number" "$comment_id" "$comment_url"
}

cmd_ready() {
  if [ $# -lt 1 ]; then
    log "Usage: github-pr.sh ready <task-id>"
    exit 1
  fi

  local task_id="$1"
  check_token

  # Get task state
  local task_json
  task_json=$(get_task "$task_id")

  local repo pr_number
  repo=$(task_field "$task_json" "repo")
  pr_number=$(task_field "$task_json" "pr_number")

  validate_pr_number "$pr_number" "$task_id"

  # Undraft the PR using GraphQL API (REST PATCH can't toggle draft on all plans)
  # First, get the node_id of the PR
  local pr_response
  pr_response=$(gh_api "GET" "/repos/${repo}/pulls/${pr_number}")

  local node_id
  node_id=$(echo "$pr_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('node_id',''))" 2>/dev/null)

  if [ -z "$node_id" ]; then
    log "ERROR: Could not get PR node_id"
    exit 3
  fi

  # Use GraphQL to mark PR as ready for review
  local graphql_data
  graphql_data=$(python3 -c "
import json
query = '''mutation {
  markPullRequestReadyForReview(input: {pullRequestId: \"NODE_ID\"}) {
    pullRequest {
      isDraft
      number
    }
  }
}'''.replace('NODE_ID', '$node_id')
print(json.dumps({'query': query}))
" 2>/dev/null)

  local gql_response
  gql_response=$(curl -s --max-time 30 \
    -H "Authorization: bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    "https://api.github.com/graphql" \
    -d "$graphql_data" 2>/dev/null)

  local is_draft
  is_draft=$(echo "$gql_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    errors = data.get('errors')
    if errors:
        print('ERROR:' + errors[0].get('message', 'Unknown'))
        sys.exit(0)
    pr = data.get('data', {}).get('markPullRequestReadyForReview', {}).get('pullRequest', {})
    print(str(pr.get('isDraft', True)).lower())
except:
    print('ERROR:Failed to parse response')
" 2>/dev/null)

  if [[ "$is_draft" == ERROR:* ]]; then
    log "ERROR: GraphQL: ${is_draft#ERROR:}"
    exit 3
  fi

  if [ "$is_draft" = "false" ]; then
    log "PR #$pr_number marked as ready for review"
  else
    log "WARNING: PR #$pr_number may still be in draft state"
  fi

  local draft_bool="true"
  [ "$is_draft" = "false" ] && draft_bool="false"

  python3 -c "
import json, sys
print(json.dumps({
    'task_id': sys.argv[1],
    'pr_number': int(sys.argv[2]),
    'draft': sys.argv[3] == 'true'
}, indent=2))
" "$task_id" "$pr_number" "$draft_bool"
}

# --- Main dispatch ---
if [ $# -lt 1 ]; then
  log "Usage: github-pr.sh <command> [args...]"
  log "Commands: create, check, comment, ready"
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  create)  cmd_create "$@" ;;
  check)   cmd_check "$@" ;;
  comment) cmd_comment "$@" ;;
  ready)   cmd_ready "$@" ;;
  *)
    log "ERROR: Unknown command '$COMMAND'. Valid: create, check, comment, ready"
    exit 1
    ;;
esac
