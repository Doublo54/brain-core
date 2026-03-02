# Orchestration Architecture Guide

Autonomous coding agent system where an orchestrator agent manages [OHO/OpenCode](https://github.com/ohmyopencode/oh-my-opencode) sessions to execute development tasks on GitHub repositories. Discord for communication, GitHub PRs for plan approval and code review.

> **Scope:** This document describes the generic orchestration architecture shipped with brain-core. For a real-world implementation reference with full version history, see your agent's implementation-specific documentation.

---

## Table of Contents

- [Architecture](#architecture)
- [Component Roles](#component-roles)
- [Key Design Decisions](#key-design-decisions)
- [Workflow](#workflow)
- [Workspace Management](#workspace-management)
- [Task State & Concurrency](#task-state--concurrency)
- [OpenCode Integration](#opencode-integration)
- [GitHub PR Integration](#github-pr-integration)
- [Monitoring & Human-in-the-Loop](#monitoring--human-in-the-loop)
- [Boot & Recovery](#boot--recovery)
- [Configuration Reference](#configuration-reference)
- [Security Considerations](#security-considerations)
- [Future Enhancements](#future-enhancements)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  OpenClaw Container                                             │
│                                                                 │
│  ┌──────────────┐    ┌──────────────────────────────────────┐  │
│  │  OpenClaw     │    │  OpenCode Server (:4096)             │  │
│  │  Gateway      │    │                                      │  │
│  │  (:18789)     │    │  ┌──────┐ ┌──────┐ ┌──────┐        │  │
│  │               │    │  │Sess 1│ │Sess 2│ │Sess 3│  ...   │  │
│  │  ┌──────────┐ │    │  │(OHO) │ │(OHO) │ │(OHO) │        │  │
│  │  │Orchestr. │─┼────▶  └──┬───┘ └──┬───┘ └──┬───┘        │  │
│  │  │Agent     │ │    │     │        │        │              │  │
│  │  └──────────┘ │    └─────┼────────┼────────┼──────────────┘  │
│  └──────────────┘          │        │        │                  │
│                            ▼        ▼        ▼                  │
│  ┌──────────────┐    /opt/opencode/                     │
│  │Discord Pipe  │    ├── repos/example-repo/ (bare clone)       │
│  │(SSE→Discord) │    ├── task-abc/ (git worktree)              │
│  │              │    ├── task-def/ (git worktree)              │
│  └──────────────┘    └── task-ghi/ (git worktree)              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Role | How |
|-----------|------|-----|
| **Orchestrator Agent** | Receives tasks, manages lifecycle, reviews plans, handles HITL | OpenClaw agent with skill + cron |
| **OpenCode Server** | Execution engine — hosts coding sessions | HTTP API at `:4096` |
| **OHO Agents** | Planning (Prometheus) → validation (Momus) → execution (Atlas/Sisyphus) | OpenCode plugin, invoked via `oho run` or HTTP API |
| **Discord Pipe** | Real-time streaming of agent activity to Discord subchannels | Standalone daemon, SSE → Discord threads |
| **GitHub API** | PR-based plan approval + code review | Direct REST API via `$GITHUB_TOKEN` |

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Orchestrator | OpenClaw agent (not standalone app) | Leverages OpenClaw tools, cron, memory, Discord integration natively |
| Task dispatch | Hybrid: HTTP API lifecycle + OHO commands (`@plan`, `/start-work`) | API for session CRUD/polling, OHO commands for agent routing — best of both worlds |
| Concurrency | Multiple git worktrees from shared repo clone | Isolated working directories, shared package store, lockfile consistency |
| Plan approval | Single GitHub PR (draft → approved → code pushed) | Less overhead than 2 PRs, inline comments for feedback |
| Streaming output | Discord pipe daemon | Routes to subchannels with per-session threading |
| Task state | JSON file in workspace + OHO's built-in todo system | Survives container restarts, queryable, git-trackable |
| Runtime management | mise per-worktree | Supports multiple Node versions, binary execution |
| Human-in-the-loop | Orchestrator polls + forwards to Discord | Idle detection + orchestrator triage (no regex guessing) |
| Agent handoff tracking | Dual: boulder.json + tasks.json | Redundant tracking for recovery after session interruptions |
| Tooling | Local binaries only | No npx/bunx — prevents supply chain risk |

---

## Workflow

### Happy Path

```
1. User: "code: add rate limiting to API endpoints"
           │
           ▼
2. Orchestrator: parse task → generate task-id → setup workspace
   - git worktree from repos/example-repo
   - install dependencies → detect runtime
   - write task to state.json
           │
           ▼
3. Orchestrator: dispatch to OpenCode via HTTP API
   - create session, inject `@plan <description>` as first message
   - @plan explicitly invokes Prometheus agent for planning
           │
           ▼
4. Orchestrator: detect plan complete (poll session idle + check .sisyphus/)
   - read plan from workspace
   - push branch, create draft PR on GitHub
   - notify Discord: "plan ready for review"
           │
           ▼
5. User: reviews PR, leaves comments or approves
           │
           ▼
6. Orchestrator: detect PR approval (poll with exponential backoff)
   - verify boulder.json shows Prometheus as active agent
   - mark PR as ready (undraft)
   - inject "/start-work" into session → Atlas executes
   - update both boulder.json tracking + tasks.json agent_state
           │
           ▼
7. During execution:
   - Discord pipe streams activity to subchannels
   - If agent needs input → orchestrator detects, forwards to Discord
   - User responds → orchestrator injects response into session
           │
           ▼
8. Orchestrator: detect execution complete
   - agent commits, pushes code to same branch
   - PR now has both plan + implementation
   - notify Discord: "code PR ready for review"
           │
           ▼
9. User: reviews code PR, merges
   - Orchestrator cleans up worktree
```

### Error Path

```
Agent error/crash → orchestrator detects failed session
  → sanitize error context before posting to Discord
  → preserves workspace for debugging
  → task marked as "failed" in state.json
  → include token cost in failure report

Timeout → phase-specific limits trigger abort
  → planning: 60 min | execution: 4 hours | idle: 10 min | total: 8 hours
  → same error flow as above

Container restart → state.json persists, sessions lost
  → orchestrator reads state on boot, reports orphaned tasks
  → cross-reference boulder.json for correct agent state
  → if agent mismatch detected → surface for manual decision
  → otherwise attempt session recovery
```

---

## Workspace Management

### Setup Script — `scripts/orchestration/setup-workspace.sh`

```
Input:  task-id, repo-url, base-branch
Output: JSON metadata (workspace path, node version, package manager)

Steps:
1. Task-id validation (regex gate — blocks path traversal + injection)
2. Repo URL validation (GitHub HTTPS only — prevents token leak to other hosts)
3. GIT_ASKPASS helper (token never in .git/config or ps aux)
4. git worktree creation with branch reuse handling
5. .gitignore append with newline safety
6. Node version detection (.nvmrc > .node-version > .tool-versions > package.json engines)
7. .mise.toml + mise trust + mise install
8. Package manager detection (packageManager field > lockfile > npm default)
9. Dependencies install with frozen-lockfile fallback + logging
10. JSON output via python3 json.dumps (proper escaping)
```

### Cleanup Script — `scripts/orchestration/cleanup-workspace.sh`

```
Input: task-id [--delete-branch]

Steps:
1. Task-id validation (same regex as setup)
2. Find parent repo via .git pointer or repos/ scan
3. git worktree remove --force with rm -rf fallback
4. Prune stale worktree refs
5. Delete local branch
6. Optional: delete remote branch via GitHub API
```

### Credential Management

Per-workspace persistent credential helper for agent git push:

- `$WORKSPACE/.git-credential-helper.sh` reads token from `$WORKSPACE/.git-token`
- Configured via `git config credential.helper` in worktree
- Cleanup script removes both files on teardown
- Per-workspace (not global) for multi-repo/multi-token support

### Repo Configuration

The orchestrator uses dynamic discovery instead of static config files:

- **Default branch:** GitHub API (`default_branch` field)
- **Runtime:** Repo files (`.nvmrc`, `packageManager`, `AGENTS.md`)
- **QA/validation:** Agent-inferred from context (AGENTS.md, package.json scripts, pre-commit hooks, CI config)
- **Timeouts:** Global defaults from SKILL.md, overridable per-repo via config files

### Environment Variable Tiers

Tasks are tiered by env var requirements, unblocking immediate work on lower tiers:

| Tier | Needs | Example Tasks | Status |
|------|-------|---------------|--------|
| 1 | Nothing | Refactoring, types, docs, lint fixes | Ready |
| 2 | `NODE_ENV` at most | Typecheck, lint | Ready |
| 3 | Database URLs, secrets | Jest, Vitest tests | Blocked on .env |
| 4 | Everything | Dev server, E2E, Playwright | Blocked on .env |

Track `env_tier` per task in tasks.json.

---

## Task State & Concurrency

### State File — `state/tasks.json`

```json
{
  "tasks": {
    "task-1738600000-a1b2": {
      "id": "task-1738600000-a1b2",
      "status": "executing",
      "repo": "example-org/example-repo",
      "branch": "agent/task-1738600000-a1b2",
      "base_branch": "main",
      "workspace": "/opt/opencode/task-1738600000-a1b2",
      "session_id": "ses_abc123",
      "description": "Add rate limiting to API endpoints",
      "pr_number": 42,
      "pr_url": "https://github.com/example-org/example-repo/pull/42",
      "created_at": "2026-02-03T18:00:00Z",
      "updated_at": "2026-02-03T19:30:00Z",
      "phase_started_at": "2026-02-03T19:30:00Z",
      "last_idle_at": null,
      "requested_by": "your-username",
      "plan_file": ".sisyphus/plans/rate-limiting.md",
      "agent_state": "atlas",
      "boulder_agent": "atlas",
      "token_usage": {
        "input": 0, "output": 0, "reasoning": 0,
        "cache_read": 0, "cache_write": 0, "cost_usd": 0.0
      },
      "env_tier": 1,
      "pre_execution_sha": null,
      "nudge_count": 0,
      "error": null
    }
  },
  "queue": [],
  "version": 2
}
```

### Status Transitions

```
created → planning → plan_review → executing → validating → code_review → completed
                  ↘ failed    ↗         ↘ failed ↗     ↘ failed ↗       ↘ failed
                    aborted               aborted        aborted          aborted

  needs_input (sub-state during planning or executing)
  timed_out (terminal — when phase timeout exceeded)
  paused (sub-state — set by monitor.sh when OpenCode server is down,
          resumes to previous status when server returns)
```

The `validating` state between `executing` and `code_review` provides a pre-merge validation gate — checks for committed artifacts, secrets, input sanitization. If validation fails, the orchestrator triages: either auto-fix (remove bad files from staging) or inject fix instructions back into the agent session.

### Timeout Configuration

Timeouts are enforced by the polling cron:

| Phase | Timeout | What Happens |
|-------|---------|-------------|
| Planning | 60 min | Abort session, mark timed_out, notify Discord |
| Execution | 4 hours | Abort session, preserve workspace, notify Discord |
| Idle detection | 10 min | Surface last message to orchestrator for triage |
| Total task TTL | 8 hours | Hard ceiling — abort regardless of phase |

```json
{
  "timeouts": {
    "planning_min": 60,
    "execution_min": 240,
    "idle_min": 10,
    "total_min": 480
  }
}
```

### Concurrency Control

| Setting | Default | Notes |
|---------|---------|-------|
| Max concurrent tasks | 3 | Per-repo configurable |
| Max total tasks | 5 | Across all repos |
| Disk budget per task | ~500MB | Worktree + node_modules |
| Queue behavior | FIFO | Excess tasks queued as `pending`, started when slot opens |

When a task completes/fails/aborts, the orchestrator checks the queue and starts the next pending task automatically.

### Dual Agent Tracking

Track agent state in both `tasks.json` AND cross-reference OHO's `boulder.json`:

```
On every poll cycle:
1. Read tasks.json → expected agent (e.g., "prometheus" during planning)
2. Read boulder.json from workspace → actual agent OHO thinks is active
3. If mismatch → flag for manual review (don't auto-correct)
4. On recovery after restart → require both sources to agree before resuming
```

This addresses the known session interruption issue where the wrong agent can resume after interruptions. Belt and suspenders — orchestrator state is the source of truth, boulder.json is the validation layer.

### Session Cleanup

When a task reaches terminal status (`completed`, `failed`, `aborted`, `timed_out`):

1. Extract last assistant message from OpenCode session (useful output / error context)
2. Store extracted output in task state (`last_output` field)
3. Delete the OpenCode session via `DELETE /session/{id}`
4. Log cleanup in task state

This prevents unbounded session growth. OpenCode never auto-deletes sessions — without cleanup, sessions accumulate indefinitely and consume memory.

---

## OpenCode Integration

### Session Lifecycle via HTTP API

| Action | Method | Endpoint | Body |
|--------|--------|----------|------|
| Create session | `POST` | `/session` | `{}` |
| Send message | `POST` | `/session/{id}/message` | `{"parts":[{"type":"text","text":"..."}]}` |
| List sessions | `GET` | `/session` | — |
| Abort session | `POST` | `/session/{id}/abort` | — |
| Delete session | `DELETE` | `/session/{id}` | — |
| Stream events | `GET` | `/event` | — (SSE) |

### Task Dispatch — Hybrid Approach

HTTP API for session lifecycle + OHO commands for agent routing:

```bash
# 1. Create session (no directory binding needed — server has global filesystem access)
SESSION=$(curl -s -X POST http://127.0.0.1:4096/session \
  -H "Content-Type: application/json" \
  -d '{}')
SESSION_ID=$(echo $SESSION | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# 2. Inject @plan command as first message → routes to Prometheus
curl -s -X POST "http://127.0.0.1:4096/session/$SESSION_ID/message" \
  -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"@plan <task prompt with context>"}]}'

# 3. After plan approval → inject /start-work → routes to Atlas
curl -s -X POST "http://127.0.0.1:4096/session/$SESSION_ID/message" \
  -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"/start-work"}]}'

# 4. Poll, abort, delete via HTTP API as before
```

**Why hybrid over pure HTTP or pure CLI:**
- HTTP API: session creation, polling, abort, delete, message injection — full lifecycle control
- `@plan`: explicitly invokes Prometheus for planning (critical — without it, Sisyphus might start coding directly)
- `/start-work`: explicitly triggers Atlas for execution after approval
- No directory binding needed — server has global filesystem access, prompt specifies workspace path

### Task Prompt Template

The first message to the session uses `@plan` to invoke Prometheus:

```markdown
@plan {{TASK_DESCRIPTION}}

## Context
- **Task:** {{TASK_ID}}
- **Repo:** {{REPO_NAME}}
- **Branch:** agent/{{TASK_ID}} (from {{BASE_BRANCH}})
- **Working directory:** {{WORKSPACE}} (use absolute paths — cd here first)

## Constraints
- All file operations must use absolute paths under {{WORKSPACE}}
- Run all shell commands from {{WORKSPACE}} (cd {{WORKSPACE}} && ...)
- Follow existing code style (see AGENTS.md, .cursor/rules/)
- Write tests for new functionality
- Keep commits atomic with descriptive messages
- Use conventional commit format
- Discover how to validate your work from the repo itself:
  check AGENTS.md, package.json scripts, pre-commit hooks, CI config
```

### Commit Rules

Append to every task prompt to enforce repo hygiene:

```markdown
## Commit Rules
- Use `git add <specific-files>` — NEVER use `git add .` or `git add -A`
- Never commit: .mise.toml, .sisyphus/boulder.json, .env, *.log, node_modules/
- Check `git status` before every commit
- Verify `git diff --cached` contains only intended changes
- Use conventional commit format: type(scope): description
```

### Pre-Merge Validation Gate

Before the orchestrator transitions a task from `executing` → `code_review`:

```
1. git diff --cached scan:
   - Deny: boulder.json, .mise.toml, .env*, *.log, node_modules/
   - Flag: files > 500 lines (review manually)
   - Flag: binary files (unexpected)
2. Secret scan:
   - Reuse pipe sanitization patterns
   - Check for tokens, connection strings, API keys in diff content
3. Input validation audit (for shell scripts):
   - Check: user-controlled inputs validated before use in paths/commands
   - Run shellcheck if bash scripts present
4. Agent-inferred QA:
   - Agent discovers how to validate from repo context:
     AGENTS.md, package.json scripts, pre-commit hooks, CI config
   - Do NOT hardcode test_commands — let the agent infer validation
   - If QA passes → proceed. If fails → inject failure context back
     into session. Abort after 3 consecutive failures
5. If any deny-list file found → auto-remove from staging, log warning
6. If secrets found → abort, surface to orchestrator
7. If shellcheck errors → surface as review comment, don't block
```

### Review-to-Prompt Format

When review findings need to be injected back into an agent session:

```markdown
## Review Fixes Required

### [CRITICAL] Fix 1: <title>
- **File:** path/to/file.sh
- **Line:** 49
- **Issue:** <description>
- **Fix:** <specific instruction>
- **Code example:**
\`\`\`bash
<suggested fix>
\`\`\`

### [MEDIUM] Fix 2: <title>
...
```

This structured format gives the agent clear, actionable instructions with file/line references.

---

## GitHub PR Integration

### PR Creation (Plan Review)

```bash
# After plan is generated and pushed:
# Note: "base" comes from task's base_branch (repo config default_branch),
# NOT hardcoded to "main" — source repo could use staging/develop/etc.
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/OWNER/REPO/pulls" \
  -d '{
    "title": "[AI] task-id: brief description",
    "head": "agent/task-id",
    "base": "{{BASE_BRANCH}}",
    "body": "## Plan\n\n<plan content>\n\n---\nApprove to start implementation.",
    "draft": true
  }'
```

### Approval Detection with Exponential Backoff

```bash
# Check for approval
curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/OWNER/REPO/pulls/NUMBER/reviews"

# Check for review comments (feedback)
curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/OWNER/REPO/pulls/NUMBER/comments"
```

- Poll with exponential backoff: 60s → 120s → 240s → max 300s (5 min cap)
- Reset to 60s on any PR activity (new review, comment, commit)
- If `APPROVED` → verify boulder.json agent state → trigger `/start-work`, mark PR ready (undraft)
- If `CHANGES_REQUESTED` → extract feedback, inject into session (review-to-prompt format), reset backoff

### Base Branch Drift

For long-running tasks, the base branch may advance:

```
1. git fetch origin {{BASE_BRANCH}}
2. git rebase origin/{{BASE_BRANCH}}
3. If conflict → surface to orchestrator with conflict file list
4. Do NOT auto-resolve conflicts (too risky for agent)
```

Base branch comes from repo config `default_branch` or task-level override. Different repos use different base branches (main, staging, develop). Never hardcode.

### Post-Implementation

- Agent pushes code to same branch
- PR automatically updates with new commits
- Orchestrator posts comment: "Implementation complete. Ready for review."
- Undraft the PR

---

## Monitoring & Human-in-the-Loop

The monitoring system uses a **two-layer architecture**: deterministic bash for routine checks, orchestrator agent for ambiguous triage. This saves significant tokens and makes deterministic checks predictable.

### Layer 1: monitor.sh (Deterministic)

Runs via cron every 60s. Handles everything that doesn't need judgment:

```bash
# For each active task in tasks.json:

# 1. OpenCode server health check
#    curl -sf http://127.0.0.1:4096/session → if fails 3x consecutive:
#    mark all active tasks as "paused", write alert

# 2. Timeout enforcement (per-phase + total TTL)
#    planning > planning_min → abort, mark timed_out, write alert
#    executing > execution_min → abort, preserve workspace, write alert
#    total TTL exceeded → hard abort regardless of phase

# 3. Idle detection + auto-nudge
#    session idle > idle_min:
#    a. Check git status in workspace
#    b. If uncommitted changes → auto-nudge: "Please commit and push."
#    c. If committed but not pushed → nudge: "Please push to origin."
#    d. If 2 nudges already sent → write alert for orchestrator triage
#    e. If no changes at all → write alert for orchestrator triage

# 4. Boulder.json cross-reference
#    Compare agent field with tasks.json agent_state
#    If mismatch → write alert (never auto-correct)

# 5. Session cleanup for terminal tasks
#    completed/failed/aborted/timed_out with session_id set → cleanup

# 6. Workspace retention enforcement
#    Terminal tasks older than retention period → cleanup workspace

# 7. Concurrency queue management
#    If active_count < max_tasks and queue non-empty → start next task
```

### Layer 2: Orchestrator Triage

The orchestrator handles alerts that require judgment:

- `idle_unresolved` → read last message, decide: question (forward to user), stuck (inject guidance), done (trigger next phase)
- `server_down` → investigate, restart if possible, notify Discord
- `agent_mismatch` → surface full context for manual decision
- `timeout` → notify Discord with task summary + cost so far

### Alert System

monitor.sh writes alerts to `state/alerts.json`:

```json
{
  "alerts": [
    {
      "id": "alert-1738700000-a1b2",
      "type": "idle_unresolved | timeout | server_down | agent_mismatch | test_failure",
      "task_id": "task-123",
      "message": "human-readable description",
      "severity": "critical | medium | low",
      "created_at": "2026-02-05T10:00:00Z",
      "resolved_at": null,
      "resolved_by": null
    }
  ],
  "version": 1
}
```

| Type | Trigger | Severity |
|------|---------|----------|
| `idle_unresolved` | 2 nudges sent, no response | medium |
| `timeout` | Phase or total TTL exceeded | critical |
| `server_down` | OpenCode unreachable 3x | critical |
| `agent_mismatch` | boulder.json ≠ tasks.json agent | critical |
| `test_failure` | 3 consecutive QA failures | medium |

### Error Taxonomy

| Type | Examples | Handler | Action |
|------|----------|---------|--------|
| **Transient** | Network timeout, API 429/503, curl failure | monitor.sh | Retry with backoff (max 3) |
| **Agent** | Stuck, wrong output, test failures, idle | monitor.sh → orchestrator | Nudge → surface for triage |
| **Infra** | OpenCode down, disk full, git corruption | monitor.sh | Pause all tasks, alert immediately |
| **Terminal** | Unrecoverable state, security issue, 3 test failures | monitor.sh | Abort, preserve workspace, alert |

### Token Cost Tracking

OpenCode API exposes per-message token data:

```json
{
  "tokens": {
    "input": 1,
    "output": 329,
    "reasoning": 0,
    "cache": { "read": 54711, "write": 304 }
  },
  "cost": 0,
  "modelID": "claude-opus-4-5",
  "providerID": "anthropic"
}
```

On each poll cycle or task completion:

1. Sum tokens across all messages via `GET /session/{id}/message`
2. Calculate cost from model rates (fallback if `cost` field is 0)
3. Update `token_usage` in tasks.json
4. On completion/failure → include cost summary in Discord notification

```
Task task-1738600000-a1b2 completed.
Plan: rate-limiting.md → PR #42
Duration: 2h 14m | Tokens: 145k in / 38k out | Est. cost: $2.18
```

### Response Injection (HITL)

- User responds in Discord: "respond task-123 use Redis for caching"
- Orchestrator injects message into session: `POST /session/{id}/message`
- Mark idle event as resolved, reset idle timer
- Clear related alerts

### Workspace Retention Policy

| Task Status | Retention | Rationale |
|-------------|-----------|-----------|
| `completed` | Immediate cleanup | Code is on the branch/PR, workspace not needed |
| `failed` / `aborted` | 48 hours | Debugging window, then auto-clean via monitor.sh |
| `timed_out` | 48 hours | Same as failed |

### Session Lifecycle Management

OpenCode sessions accumulate indefinitely. The orchestrator must manage cleanup:

| Session Type | Retention | Trigger |
|--------------|-----------|---------|
| Active task sessions | Keep until task completes | Task completion |
| Completed/idle sessions | 48h | monitor.sh cleanup |
| Orphan subagents | Delete immediately | Parent deleted / missing |

Orphan detection: check `parentID` field — if parent session doesn't exist, delete.

### Sub-Agent Review with Failover

Review workflow before surfacing PR for human review:

```
1. Orchestrator does own review (inline, with full context)
2. Spawn sub-agent for independent review (lower-cost model)
3. If sub-agent fails (~50% silent failure rate observed):
   a. Retry once
   b. If still fails → dispatch review to OpenCode session as backup
   c. If OpenCode unavailable → orchestrator does solo review with checklist
4. Consolidate findings into single table with severity + fix effort
5. Post consolidated review as PR comment
6. If critical issues → fix before surfacing to human
7. If only medium/low → surface with review summary
```

---

## Boot & Recovery

### Defensive Boot Script — `scripts/boot.sh`

```bash
#!/bin/bash
set -euo pipefail

WORKSPACE="$HOME/.openclaw/workspaces/your-agent"
LOCKFILE="/tmp/orchestrator-boot.lock"

# 1. Acquire boot lock (prevent concurrent boots)
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Boot already running"; exit 0; }

# 2. Kill orphan processes (pipe, stale orchestrator scripts)
kill_orphans() {
  pgrep -f "opencode-discord-pipe/pipe.ts" | while read pid; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  pgrep -f "opencode-discord-pipe/pipe.ts" | while read pid; do
    kill -KILL "$pid" 2>/dev/null || true
  done
}
kill_orphans

# 3. Health check: OpenCode server
wait_for_opencode() {
  local retries=30
  while [ $retries -gt 0 ]; do
    curl -sf http://127.0.0.1:4096/session >/dev/null 2>&1 && return 0
    retries=$((retries - 1))
    sleep 2
  done
  echo "ERROR: OpenCode server not responding after 60s"
  return 1
}
wait_for_opencode

# 4. Start Discord pipe (uses local binary, not npx)
bash "$WORKSPACE/opencode-discord-pipe/daemon.sh" start

# 5. Health check: pipe
sleep 3
bash "$WORKSPACE/opencode-discord-pipe/daemon.sh" status || {
  echo "WARNING: Pipe failed to start"
}

echo "Boot complete"
```

### Post-Restart Recovery

The orchestrator reads `state/tasks.json` on first session after boot.

**Available recovery context per task:**
- `tasks.json` — status, phase, session_id, pre_execution_sha, branch, description
- `.sisyphus/plans/` — Prometheus plan (if planning completed)
- `boulder.json` — OHO's view of active agent
- `git log` / `git status` — work done, uncommitted changes
- PR comments — review feedback if any was posted

**Recovery flow per task state:**

| State at Restart | Session Exists? | Agent Match? | Action |
|-----------------|----------------|--------------|--------|
| `planning` | yes | yes | Resume monitoring |
| `planning` | no | — | New session, re-inject `@plan` with note about existing partial plan |
| `plan_review` | — | — | Check if PR exists. If yes, resume polling. If no, re-create PR |
| `executing` | yes | yes | Resume monitoring |
| `executing` | no | yes | New session, inject continuation prompt with branch/plan/git state |
| `executing` | no | no | **Surface for manual decision.** Never auto-resume on agent mismatch |
| `validating` | — | — | Re-run validation gate from scratch |
| Any | — | mismatch | **Always surface.** Never auto-resume on agent mismatch |

Report recovery status to Discord: which tasks resumed, which need attention, which are blocked on manual decision.

---

## Configuration Reference

### Orchestrator Skill Structure

```
skills/coding-orchestrator/
├── SKILL.md              # Instructions for orchestrator agent
├── scripts/
│   ├── setup-workspace.sh
│   ├── cleanup-workspace.sh
│   └── monitor.sh        # Deterministic monitoring layer
├── templates/
│   ├── task-prompt.md
│   └── oho-config.json
├── config/
│   └── repos/            # Per-repo config overrides (optional)
└── state/
    └── tasks.json
```

### SKILL.md Triggers

| User Command | Action |
|-------------|--------|
| `code <description> [on <repo>]` | Start task flow |
| `status` | Show active tasks + token cost |
| `approve <task-id>` | Verify agent state, trigger execution |
| `abort <task-id>` | Abort and cleanup |
| `respond <task-id> <message>` | Inject into session |
| `cleanup sessions` | Run immediate session cleanup |

### Orchestrator-Level Sanitization

Everything the orchestrator surfaces to Discord must be sanitized:

- Error messages from failed sessions
- Plan content (may reference env vars, connection strings)
- Question forwarding (agent might quote sensitive config)
- Task completion reports

Reuse the same sanitization patterns from the Discord pipe (`formatter.ts:sanitizeOutput`).

---

## Security Considerations

| Risk | Mitigation |
|------|-----------|
| Agent reads secrets via filesystem | Scope worktree to `/opt/opencode/` (not `/`) |
| Secrets leaked to Discord | Orchestrator-level sanitization on all output |
| Orphan processes from restarts | Defensive boot script + pipe foreground supervisor |
| Supply chain attacks via npx/bunx | Local binaries only — no dynamic downloads |
| OpenCode server dies mid-task | monitor.sh health check every 60s, pause after 3 failures |
| Base branch drifts during long tasks | Rebase against base_branch before PR creation |
| Agent code breaks the branch | Rollback via `git reset --hard $pre_execution_sha` |
| Wrong agent resumes after interruption | Dual tracking (tasks.json + boulder.json), never auto-resume on mismatch |
| Too many parallel tasks exhaust resources | Max 3 per repo, 5 total, FIFO queue, ~500MB per worktree |
| Session accumulation | Automated cleanup: orphan detection + 48h retention |

---

## Future Enhancements

- [ ] Webhook-based PR approval (replace polling entirely)
- [ ] GitHub Actions integration — run CI before PR approval
- [ ] Multi-repo support with shared workspace management
- [ ] Metrics dashboard — aggregate token usage, completion rates across tasks
- [ ] Auto-retry on transient failures (with exponential backoff)
- [ ] LSP server integration for better code intelligence
- [ ] Adaptive timeouts — learn from historical task durations per repo
- [ ] Preview deployments — auto-deploy PR branches for visual feedback during execution
- [ ] Project management integration — auto-create tasks from external sources

---

## Learnings & Best Practices

These patterns emerged from production usage of the orchestration system.

### Agent Behavior Patterns

1. **Agents go idle after applying fixes without committing** (~66% of the time). Auto-nudge via monitor.sh is critical for throughput.
2. **Structured review-to-prompt format works** — agents follow fix instructions precisely when given file/line/issue/fix structure.
3. **Commit rules in prompt are followed when explicit** — "never `git add .`" is respected.
4. **Cross-task learning is real** — agents learn patterns (e.g., .gitignore) established in previous tasks.

### Code Quality Insights

1. **Agents write functionally correct code but miss repo hygiene and security edge cases.** The orchestrator's job isn't just lifecycle management — it's the quality gate that compensates for what LLMs consistently get wrong.
2. **Code review (even from multiple sources) is necessary but not sufficient.** Testing against real repos catches runtime/environment issues invisible in static review.
3. **Dual independent reviews catch 30-50% more issues** than single review. The orchestrator + sub-agent pattern is worth the ~3 min / ~55k tokens per cycle.

### Infrastructure Lessons

1. **Daemon processes in containers need foreground supervisors**, not backgrounded subshells. Docker reaps orphaned background processes silently.
2. **OpenCode never auto-deletes sessions.** Without active cleanup, sessions accumulate and consume memory.
3. **Per-workspace credential helpers** are safer and more flexible than global git credential config.
4. **`mise trust` must be called explicitly** — every new workspace fails without it. Runtime behaviors are invisible in code review.

---

*This document describes the generic orchestration architecture. For implementation-specific details including version history, PR review learnings, and phase completion tracking, see your agent's orchestration documentation.*
