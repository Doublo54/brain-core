---
name: coding-orchestrator
description: "Orchestrate OpenCode agent sessions to execute coding tasks on GitHub repos. Use when user says 'code: <description>' or 'code <description> on <repo>', or asks for 'task status', 'approve <task-id>', 'abort <task-id>', or 'respond <task-id> <message>'. Also use for OpenCode session management, cleanup, and API interactions."
metadata: { "openclaw": { "emoji": "🎭", "requires": { "bins": ["opencode"], "env": ["GITHUB_TOKEN"] } } }
---

# Coding Orchestrator Skill

Orchestrate OpenCode agent sessions to execute coding tasks on GitHub repos.
Discord for comms, GitHub PRs for plan approval and code review.

## Trigger

When user says **"code: <description>"** or **"code <description> on <repo>"** → start task flow.

Other commands:
- **"task status"** / **"tasks"** → show active tasks (include token cost from `token_usage` field)
- **"approve <task-id>"** → trigger execution phase
- **"abort <task-id>"** → abort task and cleanup
- **"respond <task-id> <message>"** → inject message into agent session
- **"cleanup sessions"** → run session cleanup (orphan detection, 48h retention)

---

## OpenCode HTTP API Reference (v1.1.48)

OpenCode runs at `http://127.0.0.1:4096`. Use these endpoints for programmatic control.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/session` | List all sessions (returns JSON array) |
| GET | `/session/:id` | Get session details |
| DELETE | `/session/:id` | Delete session |
| GET | `/session/:id/message` | Get session messages |
| POST | `/session/:id/message` | Send message (needs `parts` array) |
| GET | `/agent` | List available agents |

### Session Object

```json
{
  "id": "ses_xxx",
  "slug": "calm-garden",
  "version": "1.1.48",
  "projectID": "xxx",
  "directory": "/path/to/workspace",
  "parentID": "ses_parent_xxx",
  "title": "Session title",
  "time": { "created": 1770346723188, "updated": 1770397685068 },
  "summary": { "additions": 0, "deletions": 0, "files": 0 }
}
```

### Sending Messages

```bash
# Correct: parts array with agent field
curl -X POST http://localhost:4096/session/${SESSION_ID}/message \
  -H "Content-Type: application/json" \
  -d '{"agent": "prometheus", "parts": [{"type": "text", "text": "your task description"}]}'

# Wrong: content object (will fail validation)
curl -X POST ... -d '{"content": "text"}'  # ❌
```

### Error Patterns

| Response | Meaning |
|----------|---------|
| HTML with `<!doctype html>` | Wrong endpoint (SPA fallback). Try `/session` not `/api/session` |
| `{"error":[...], "success":false}` | Validation error (check parts format) |
| Empty array `[]` | No sessions exist |
| Exit code 2 from status check | Session not found |

### Agent Triggering

Agent selection is controlled via the `--agent` flag in `opencode-session.sh send`:
- **Prometheus (planning)**: `--agent prometheus` (planning only, writes to .sisyphus/plans/, no code)
- **Atlas (execution)**: `--agent atlas` (execution from plan, or via `/start-work` slash command in message)
- **Sisyphus (default)**: `--agent sisyphus` or omit flag (general purpose, plans + codes)

**Example:**
```bash
bash /opt/scripts/orchestration/opencode-session.sh send "$SESSION_ID" "/tmp/prompt.md" \
  --agent prometheus \
  --workspace "$WORKSPACE"
```

---

## Session Lifecycle Management

### Problem
OpenCode sessions accumulate indefinitely. Each Prometheus run spawns 5-10+ subagents that persist after completion.

### Cleanup Commands

```bash
# List all sessions with age
curl -s http://localhost:4096/session | python3 -c "
import sys, json
from datetime import datetime
sessions = json.load(sys.stdin)
now = datetime.now().timestamp() * 1000
for s in sessions:
    age_h = (now - s['time']['updated']) / 3600000
    print(f\"{s['id'][:20]}... {s.get('title','untitled')[:40]} ({age_h:.1f}h old)\")
"

# Delete sessions older than N hours
MAX_HOURS=48
CUTOFF_MS=$(python3 -c "import time; print(int((time.time() - $MAX_HOURS*3600) * 1000))")
curl -s http://localhost:4096/session | python3 -c "
import sys, json
for s in json.load(sys.stdin):
    if s['time']['updated'] < $CUTOFF_MS:
        print(s['id'])
" | while read sid; do
    curl -s -X DELETE "http://localhost:4096/session/$sid"
done

# Delete orphan subagents (parent session gone)
curl -s http://localhost:4096/session | python3 -c "
import sys, json
sessions = json.load(sys.stdin)
ids = {s['id'] for s in sessions}
for s in sessions:
    if s.get('parentID') and s['parentID'] not in ids:
        print(f\"Orphan: {s['id']} (parent {s['parentID']} missing)\")
"
```

### Retention Policy

| Session Type | Retention | Cleanup Trigger |
|--------------|-----------|-----------------|
| Active task sessions | Keep until task completes | Task completion |
| Completed task sessions | 48h after completion | Cron/monitor |
| Orphan subagents | Delete immediately | Parent deleted |
| Idle sessions (no task) | 48h | Cron/monitor |

---

## Scripts & Files

Scripts are baked into the Docker image at `/opt/scripts/orchestration/`. State and config live in the dynamic workspace (`$WORKSPACE`).

| Script | Purpose |
|--------|---------|
| `/opt/scripts/orchestration/setup-workspace.sh` | Create git worktree, install deps, configure credentials |
| `/opt/scripts/orchestration/cleanup-workspace.sh` | Remove worktree, credentials, prune refs |
| `/opt/scripts/orchestration/task-manager.sh` | Task state CRUD (create/status/update/get/list/delete) |
| `/opt/scripts/orchestration/opencode-session.sh` | OpenCode HTTP API wrapper (create/send/status/list/abort/delete) |
| `/opt/scripts/orchestration/github-pr.sh` | GitHub PR operations (create draft/check reviews/comment/ready) |
| `/opt/scripts/orchestration/monitor.sh` | Deterministic monitoring (timeouts, nudge, health, cleanup, alerts) |
| `/opt/scripts/orchestration/execute-task.sh` | Guarded execution trigger with Gateway approval gate |
| `/opt/scripts/orchestration/gated-execute.sh` | Gateway-interceptable wrapper (human approval enforcement) |

| File | Purpose |
|------|---------|
| `$WORKSPACE/state/tasks.json` | Persistent task state |
| `$WORKSPACE/state/alerts.json` | Unresolved alerts from monitor.sh for the orchestrator agent to triage |
| `$WORKSPACE/templates/plan-prompt.md` | Template for planning prompt (sent with --agent prometheus) |
| `$WORKSPACE/templates/fix-prompt.md` | Template for review fix injection |
| `$WORKSPACE/config/gateway-approval-config.yaml` | OpenClaw Gateway config for exec approval |

---

## On Session Start (Boot Recovery)

Every new session, before anything else:

### 1. Check for in-progress tasks

```bash
ACTIVE=$(bash /opt/scripts/orchestration/task-manager.sh list --active)
# Returns JSON array of non-terminal tasks
```

If no active tasks → skip to normal operation.

### 2. For each active task, determine recovery action

For each task, check if its OpenCode session still exists:

```bash
SESSION_ID=$(echo "$TASK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))")
# Check if session exists: bash /opt/scripts/orchestration/opencode-session.sh status "$SESSION_ID"
# If exit code 2 (not found) → session is gone
```

If workspace exists, check agent state:
```bash
BOULDER="$WORKSPACE/.sisyphus/boulder.json"
# If boulder.json exists, read the agent field
# Compare with task's agent_state in tasks.json
```

### 3. Recovery decision table

| Task status | Session exists? | Agent match? | Action |
|-------------|----------------|--------------|--------|
| `planning` | yes | yes | Resume monitoring — check if plan appeared in `.sisyphus/plans/` |
| `planning` | no | — | New session, re-inject planning prompt with `--agent prometheus` and note: "partial plan may exist at .sisyphus/, check before replanning" |
| `plan_review` | — | — | Check if PR exists on GitHub (by pr_number). If yes → wait for approval. If no → re-create PR from plan |
| `executing` | yes | yes | Resume monitoring — check git log for new commits since phase_started_at |
| `executing` | no | yes | New session, inject recovery prompt (see below) |
| `executing` | no | no | **ESCALATE to Discord.** Show: expected agent, boulder agent, `git log --oneline -5`, `git status`. Never auto-resume |
| `validating` | — | — | Re-run validation gate from scratch |
| `code_review` | — | — | Check PR status on GitHub. If approved → transition to qa. If open → wait |
| `qa` | — | — | Check QA status. If `qa_approved_at` exists → transition to completed. If pending → wait for QA feedback |
| Any state | — | mismatch | **ALWAYS ESCALATE.** Never auto-resume on agent mismatch |

### 4. Recovery prompt for executing + no session

```
Continue work on task {{TASK_ID}}.
Branch: agent/{{TASK_ID}}, workspace: {{WORKSPACE}}
Plan: see .sisyphus/plans/ for the original plan.

Check progress:
- git log --oneline origin/{{BASE_BRANCH}}..HEAD (what's been done)
- git status (uncommitted work)
- git diff (work in progress)

Complete remaining items from the plan. Commit and push when done.
```

Include `pre_execution_sha` if available — agent can diff against it to see total changes.

### 5. Report to Discord

After recovery scan, report:
- Tasks resumed automatically (with status)
- Tasks needing manual attention (with context)
- Tasks in terminal state (no action needed)

---

## Task Lifecycle

### 1. Create Task

```bash
# Generate task ID
TASK_ID="task-$(date +%s)-$(head -c 4 /dev/urandom | xxd -p)"

# Parse repo from user command:
#   "code X on example-org/example-repo" → REPO_SLUG="example-org/example-repo"
#   "code X on https://github.com/example-org/example-repo" → strip prefix
# Repo MUST be specified — no default. Fail if missing.
REPO_URL="https://github.com/${REPO_SLUG}"

# Discover default branch from GitHub API (not hardcoded)
BASE_BRANCH=$(curl -sf -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/${REPO_SLUG}" | python3 -c "import sys,json; print(json.load(sys.stdin)['default_branch'])")

# Create task in state
bash /opt/scripts/orchestration/task-manager.sh create "$TASK_ID" "$REPO_SLUG" "$DESCRIPTION" \
  --base-branch "$BASE_BRANCH" --requested-by "$OWNER"

# Setup workspace
METADATA=$(bash /opt/scripts/orchestration/setup-workspace.sh "$TASK_ID" "$REPO_URL" "$BASE_BRANCH")
WORKSPACE=$(echo "$METADATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace'])")
```

### 2. Dispatch to OpenCode (Planning)

```bash
# Create OpenCode session
SESSION_ID=$(bash /opt/scripts/orchestration/opencode-session.sh create)

# Store session ID in task state
bash /opt/scripts/orchestration/task-manager.sh update "$TASK_ID" session_id "$SESSION_ID"
bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" planning

# Render plan prompt from template with task context
bash /opt/scripts/orchestration/render-plan-prompt.sh "$TASK_ID" "/tmp/prompt-${TASK_ID}.md"

# Send to Prometheus agent with workspace context
bash /opt/scripts/orchestration/opencode-session.sh send "$SESSION_ID" "/tmp/prompt-${TASK_ID}.md" \
  --agent prometheus \
  --workspace "$WORKSPACE"
```

**Critical:** Always use `render-plan-prompt.sh` to inject Communication rules (question tool prohibition) and Commit Rules.

**After sending:** notify Discord that planning has started.

### 3. Detect Plan Complete

Poll the session for idle state. When agent stops responding:
- Check if `.sisyphus/plans/` exists in the workspace
- Push branch and create draft PR:

```bash
PR_RESULT=$(bash /opt/scripts/orchestration/github-pr.sh create "$TASK_ID")
PR_URL=$(echo "$PR_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['pr_url'])")
```

**Notify Discord:** "Plan ready for review: <PR_URL>"

### 4. Handle Approval

When user says **"approve <task-id>"**:

```bash
# Verify task is in plan_review
TASK=$(bash /opt/scripts/orchestration/task-manager.sh get "$TASK_ID")

# Undraft the PR
bash /opt/scripts/orchestration/github-pr.sh ready "$TASK_ID"

# Transition to approved and trigger execution
bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" approved
bash /opt/scripts/orchestration/execute-task.sh "$TASK_ID"
```

**Auto-approve / force bypass:**
- `auto_approve` is a **protected field** — can only be set at task creation via `--auto-approve`
- Cannot be modified via `task-manager.sh update` (prevents agents from bypassing the gate)
- `execute-task.sh --force` bypasses Gateway approval but requires task status = `approved`
- Human must explicitly enable auto-approve at creation time

### 5. Detect Execution Complete + Validation Gate

When agent appears done:

```bash
cd "$WORKSPACE"

# 1. Deny-list scan
DENY_PATTERNS="boulder\.json|\.mise\.toml|\.env($|\.)|.*\.log$|node_modules"
DENY_FILES=$(git diff --cached --name-only | grep -E "$DENY_PATTERNS" || true)
# Iterate line-by-line to handle filenames with spaces
echo "$DENY_FILES" | while IFS= read -r file; do
  [ -n "$file" ] && git reset HEAD -- "$file"
done

# 2. Secret scan — ABORT on secrets
SECRETS_FOUND=$(git diff --cached | grep -iE \
  '(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|(password|passwd|pwd|pass)[[:space:]]*[:=]|api[_-]?key[[:space:]]*[:=]|mongodb(\+srv)?://|postgres(ql)?://|redis://|mysql://|-----BEGIN [^-]* KEY|Bearer[[:space:]]+[A-Za-z0-9_-]{20,}|sk-[a-zA-Z0-9]{20,})' || true)
if [ -n "$SECRETS_FOUND" ]; then
  bash /opt/scripts/orchestration/task-manager.sh update "$TASK_ID" error "Secret detected in diff — aborted (details redacted)"
  bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" failed
  exit 1
fi

# 3. Push and transition to code review
git push origin "agent/${TASK_ID}"
bash /opt/scripts/orchestration/github-pr.sh comment "$TASK_ID" "Implementation complete. Ready for code review."
bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" code_review
```

**Note:** Transitioning to `code_review` triggers a Discord notification for PR review.

### 6. QA State & Feedback Injection

After code review approves, the task enters the `qa` state for quality assurance testing.

#### QA State Entry

When a task transitions to `qa`:
- A Discord notification is sent: "🔍 **Task QA Review** — Task #{id}: {title}"
- The `qa_entered_at` timestamp is set
- QA testers can review the implementation on the branch

#### QA Feedback Injection

QA feedback is injected via Discord messages that route back to the agent session:

```bash
# QA tester sends feedback via Discord (handled by Discord pipe)
# The orchestrator receives the feedback and injects it into the agent session

bash /opt/scripts/orchestration/opencode-session.sh send "$SESSION_ID" - <<EOF
QA Feedback for task ${TASK_ID}:

${QA_FEEDBACK_MESSAGE}

Please address these issues and re-validate.
EOF

# Transition back to executing for fixes
bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" executing
```

This increments the `qa_rejection_count` field in the task state.

#### QA Approval Flow

When QA approves the task:

```bash
# Transition to completed
bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" completed

# This sets the qa_approved_at timestamp
```

#### Agent Handling of QA Feedback

When the agent receives QA feedback:
1. Read and understand the QA issues
2. Apply fixes to the code
3. Commit changes with clear messages referencing QA feedback
4. Re-run validation (transition to `validating`)
5. If validation passes, return to `qa` state for re-review

#### QA State Transitions

Valid transitions from `qa`:
- `qa` → `completed` (QA approves)
- `qa` → `executing` (QA finds issues, send back for fixes)
- `qa` → `blocked` (external blocker)
- `qa` → `aborted` (task cancelled)

### 7. Completion / Cleanup

After QA marks the task `completed` and the PR is merged:

```bash
bash /opt/scripts/orchestration/opencode-session.sh delete "$SESSION_ID"
bash /opt/scripts/orchestration/cleanup-workspace.sh "$TASK_ID"
```

---

## Performance Metrics

The orchestrator tracks performance metrics for all tasks to measure efficiency and quality.

### Metrics Tracked

| Metric | Description | Computed When |
|--------|-------------|---------------|
| `cycle_time_seconds` | Total time from task creation to completion | Auto-computed on `completed` status |
| `validation_attempts` | Number of times validation was run | Incremented on each `validating` transition |
| `first_attempt_pass` | Whether validation passed on first try | Set when transitioning from `validating` to `code_review` |
| `token_usage` | Input/output tokens and cost | Set via `set-tokens` command |

### Recording Token Usage

After task completion, record token usage from OpenCode session stats:

```bash
INPUT_TOKENS=5000
OUTPUT_TOKENS=2500
COST_USD=0.15

bash /opt/scripts/orchestration/task-manager.sh set-tokens "$TASK_ID" "$INPUT_TOKENS" "$OUTPUT_TOKENS" "$COST_USD"
```

### Viewing Metrics

**Overall statistics:**
```bash
bash /opt/scripts/orchestration/metrics.sh summary
```

Output:
```
📊 **Coding Orchestrator Metrics**
────────────────────────────
Tasks completed (all time): 42
Tasks completed (this week): 7
Average cycle time: 2h 15m
First-attempt pass rate: 85%
Total tokens used: 1,250,000
Average tokens per task: 29,762
────────────────────────────
```

**This week's statistics:**
```bash
bash /opt/scripts/orchestration/metrics.sh weekly
```

**Single task metrics:**
```bash
bash /opt/scripts/orchestration/metrics.sh task task-1738600000-a1b2c3d4
```

Output:
```
📊 **Metrics for task-1738600000-a1b2c3d4**
────────────────────────────
Status: completed
Description: Add user authentication to API
Cycle time: 3h 45m
Validation attempts: 1
First-attempt pass: ✅ Yes
Tokens: 45,000 (in: 30,000, out: 15,000)
Cost: $0.2250
────────────────────────────
```

### Discord Commands

Users can request metrics via Discord:

- **"metrics"** or **"stats"** → show overall summary
- **"metrics weekly"** → show this week's stats
- **"metrics <task-id>"** → show single task metrics

The orchestrator should call `metrics.sh` and post the formatted output to Discord.

### Metrics Schema

Tasks in `tasks.json` include these metrics fields:

```json
{
  "id": "task-1738600000-a1b2c3d4",
  "status": "completed",
  "created_at": "2025-02-01T10:00:00Z",
  "completed_at": "2025-02-01T13:45:00Z",
  "cycle_time_seconds": 13500,
  "validation_attempts": 1,
  "first_attempt_pass": true,
  "token_usage": {
    "input": 30000,
    "output": 15000,
    "cost_usd": 0.225
  }
}
```

---

## Error Handling

### Agent Timeout
If no activity within 10 min:
1. Check `git status` for uncommitted changes
2. If changes exist → nudge agent
3. If no changes after 2 nudges → escalate to Discord

### Agent Failure
1. Extract last message from session
2. If `pre_execution_sha` exists → rollback
3. Mark task as failed
4. Preserve workspace 48h for debugging
5. Notify Discord with sanitized error

### Abort
```bash
bash /opt/scripts/orchestration/opencode-session.sh abort "$SESSION_ID"
bash /opt/scripts/orchestration/task-manager.sh status "$TASK_ID" aborted
bash /opt/scripts/orchestration/cleanup-workspace.sh "$TASK_ID"
```

---

## Sanitization

**Before posting to Discord:**
- Strip GitHub tokens (ghp_*, gho_*, github_pat_*)
- Strip secrets (password=, token=, secret=, api_key=)
- Strip connection strings (mongodb://, postgres://)
- Truncate to 2000 chars

---

## Defaults

| Setting | Default |
|---------|---------|
| Planning timeout | 60 min |
| Execution timeout | 4 hours |
| Idle timeout | 10 min |
| Total TTL | 8 hours |
| Max concurrent tasks | 3 |
| Session retention | 48h |

---

## Environment

- OpenCode server: `http://127.0.0.1:4096`
- GitHub token: `$GITHUB_TOKEN`
- Workspaces root: `$WORKSPACE` (resolved dynamically per agent)

---

## Important Notes

- **Never hardcode "main"** — query GitHub API for `default_branch`
- **Use `--agent prometheus`** for planning phase — don't rely on text-based routing
- **/start-work** triggers Atlas execution — don't send prematurely
- **Agent mismatch = always escalate** — never auto-resume
- **HTML response = wrong endpoint** — use `/session` not `/api/session`
- **Question tool cannot be answered via API** — template explicitly forbids it; if agent asks question anyway, must answer via Discord interface
