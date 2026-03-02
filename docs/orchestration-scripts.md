# Orchestration Scripts Path Resolution Strategy

Task reference: Plan checkbox `3. Design Script Path Resolution Strategy`.

Status: Design only. No script implementation changes are included in this document.

## 1) Overview

This document defines a path-resolution strategy for orchestration scripts that are baked into the Docker image at:

- `/opt/scripts/orchestration/`

and executed in multi-agent runtime contexts where each agent has a distinct workspace.

### Why this is required

The original Carpincho scripts were designed around a single-brain filesystem shape where script location and mutable runtime data were colocated.

Historical assumptions in legacy scripts:

- scripts at `~/.../crapincho-brain/scripts/`
- mutable state at `../state`
- templates/config near script tree
- one fixed workspace root
- one fixed token variable `GITHUB_TOKEN_carpincho`

In brain-core deployment this breaks because:

- scripts are image-baked and read-only under `/opt/scripts/orchestration/`
- workspaces are mutable and agent-specific under host-mounted volumes
- script location is no longer a reliable anchor for mutable path discovery
- multiple agents share the same script binaries but must not share mutable state

### Primary design objective

Replace `SCRIPT_DIR/../...` state/config coupling with explicit workspace resolution.

### Non-goals

- No shell script implementation in this task
- No Dockerfile edits in this task
- No behavior redesign outside path/token/config/state resolution

## 2) Inventory Scope and Reality Check

The request listed a historical script set including names like `list-tasks.sh`, `create-coding-task.sh`, `run-task.sh`, and `alert-on-stuck-task.sh`.

The actual directory analyzed is:

- `brains-old/crapincho-brain/scripts/`

Actual scripts found (14 total):

1. `task-manager.sh`
2. `monitor.sh`
3. `daemon-monitor.sh`
4. `opencode-session.sh`
5. `setup-workspace.sh`
6. `github-pr.sh`
7. `cleanup-workspace.sh`
8. `test-orchestrator.sh`
9. `test-approval-gate.sh`
10. `execute-task.sh`
11. `gated-execute.sh`
12. `opencode-orphan-cleanup.sh`
13. `opencode-session-cleanup.sh`
14. `render-plan-prompt.sh`

All 14 scripts above are covered in this document.

## 3) Core Resolution Model

### 3.1 Workspace discovery order (mandatory)

All scripts that need mutable filesystem paths MUST resolve `WORKSPACE` in this order:

1. Environment variable: `WORKSPACE`
2. First positional argument: `$1`
3. Current directory fallback: `$(pwd)`

Canonical pattern:

```bash
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
```

### 3.2 Script location is immutable, workspace is mutable

- `SCRIPT_DIR` remains valid for locating sibling executable scripts in `/opt/scripts/orchestration/`
- `SCRIPT_DIR` MUST NOT be used to locate mutable runtime state
- mutable paths MUST be derived from `WORKSPACE`

### 3.3 Required workspace layout

All mutable artifacts should resolve under workspace:

```text
$WORKSPACE/
  state/
    tasks.json
    alerts.json
    monitor-daemon.pid
    monitor-daemon.log
    .health_failures
    locks/
  config/
    repo-configs/
    templates/
  .sisyphus/
```

### 3.4 Safe defaults

If a script is invoked without `WORKSPACE`, behavior should still be deterministic:

- fallback to `$1` if command semantics permit
- else fallback to current process cwd
- reject dangerous or empty values

Validation baseline:

- resolved `WORKSPACE` must be absolute path
- resolved `WORKSPACE` must exist for read-write operations
- state/config directory creation must be explicit (`mkdir -p`)

## 4) Environment Variable Conventions

### 4.1 Required variables

- `WORKSPACE`: absolute per-agent workspace root
- `AGENT_ID`: stable agent identifier (example: `carpincho`, `default`, `atlas`)

### 4.2 Optional variables

- `WORKSPACES_ROOT`: optional root for task workspaces in setup/cleanup scripts
- `OPENCODE_URL`: unchanged API endpoint config
- `GITHUB_TOKEN`: shared default token

### 4.3 Normalized naming

Use one workspace variable across scripts:

- preferred: `WORKSPACE`
- avoid introducing both `WORKSPACE_ROOT` and `WORKSPACE` for same meaning

Use one state anchor:

- preferred: `STATE_DIR="${WORKSPACE}/state"`

Use one config anchor:

- preferred: `CONFIG_DIR="${WORKSPACE}/config"`

## 5) Per-Agent State Isolation Strategy

### Requirement

Every running agent instance MUST have isolated state under its own workspace.

### Rule

- state lives in `"$WORKSPACE/state"`
- no script may write mutable state under `/opt/scripts/...`
- no script may write mutable state under another agent workspace

### Isolation examples

Agent A:

- `WORKSPACE=/home/node/.openclaw/workspaces/agent-a`
- `STATE_DIR=/home/node/.openclaw/workspaces/agent-a/state`

Agent B:

- `WORKSPACE=/home/node/.openclaw/workspaces/agent-b`
- `STATE_DIR=/home/node/.openclaw/workspaces/agent-b/state`

No cross-agent file collisions:

- `tasks.json`
- `alerts.json`
- locks
- monitor PID/log

## 6) Per-Agent Config Strategy

### Requirement

Configuration assets should resolve from workspace, not script install location.

### Rule

- `CONFIG_DIR="$WORKSPACE/config"`
- repo configs in `"$CONFIG_DIR/repo-configs"`
- templates in `"$CONFIG_DIR/templates"`

### Motivation

- Allows per-agent repository preferences
- Allows per-agent prompt/template variants
- Avoids coupling to immutable image path

## 7) GitHub Token Resolution Strategy

### Required fallback order

1. Per-agent override `GITHUB_TOKEN_${AGENT_ID}`
2. Shared fallback `GITHUB_TOKEN`

### Canonical resolution pattern

```bash
AGENT_ID="${AGENT_ID:-default}"
TOKEN_VAR="GITHUB_TOKEN_${AGENT_ID}"
GITHUB_TOKEN="${!TOKEN_VAR:-$GITHUB_TOKEN}"
```

### Validation behavior

- if resulting `GITHUB_TOKEN` is empty, fail with explicit error
- logs must mention missing effective token, not legacy variable names

### Compatibility note

Legacy variable `GITHUB_TOKEN_carpincho` should be treated as a migration alias only during implementation phase; design target is generic per-agent pattern.

## 8) Common Refactoring Patterns

### 8.1 Legacy state anchor replacement

Old:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/../state"
```

New:

```bash
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
STATE_DIR="${WORKSPACE}/state"
```

### 8.2 Legacy fixed workspace replacement

Old:

```bash
WORKSPACE_ROOT="/home/node/.openclaw/workspaces/carpincho"
```

New:

```bash
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
```

### 8.3 Legacy fixed scripts path in test harnesses

Old:

```bash
SCRIPTS="/home/node/.openclaw/workspaces/carpincho/scripts"
```

New:

```bash
SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/scripts/orchestration}"
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
```

### 8.4 Legacy token variable replacement

Old:

```bash
GITHUB_TOKEN="${GITHUB_TOKEN_carpincho:-}"
```

New:

```bash
AGENT_ID="${AGENT_ID:-default}"
TOKEN_VAR="GITHUB_TOKEN_${AGENT_ID}"
GITHUB_TOKEN="${!TOKEN_VAR:-$GITHUB_TOKEN}"
```

### 8.5 SCRIPT_DIR usage guidance

Keep `SCRIPT_DIR` for executable sibling scripts:

- `bash "$SCRIPT_DIR/task-manager.sh"`
- `bash "$SCRIPT_DIR/opencode-session.sh"`

Replace `SCRIPT_DIR` for mutable runtime artifacts:

- state
- config
- logs
- pid files

## 9) Refactoring Pattern Table (Old -> New)

| Category | Old Pattern | New Pattern | Rationale |
|---|---|---|---|
| State root | `${SCRIPT_DIR}/../state` | `${WORKSPACE}/state` | decouple mutable state from image path |
| Fixed workspace root | `/home/node/.openclaw/workspaces/carpincho` | `${WORKSPACE}` | enable multi-agent dynamic runtime |
| Script test path | `/home/node/.openclaw/workspaces/carpincho/scripts` | `${SCRIPTS_DIR:-/opt/scripts/orchestration}` | image-baked scripts path |
| Token source | `GITHUB_TOKEN_carpincho` | `GITHUB_TOKEN_${AGENT_ID}` -> `GITHUB_TOKEN` | per-agent override + shared fallback |
| Templates root | `${SCRIPT_DIR}/../templates` or `${WORKSPACE_ROOT}/templates` | `${WORKSPACE}/config/templates` | per-agent config isolation |
| Repo config root | implicit or script-relative | `${WORKSPACE}/config/repo-configs` | explicit per-agent config layout |
| Monitor pid/log | `${WORKSPACE}/state/monitor-daemon.*` with fixed workspace | `${WORKSPACE}/state/monitor-daemon.*` from dynamic workspace | preserve file names, make workspace dynamic |
| Locks | `${STATE_DIR}/locks` from script-relative state | `${WORKSPACE}/state/locks` | avoid shared locks across agents |

## 10) Script-by-Script Analysis

This section covers all 14 scripts.

### 10.1 `task-manager.sh`

Current path patterns:

- line 28: `SCRIPT_DIR=...`
- line 29: `STATE_DIR="${SCRIPT_DIR}/../state"`
- line 30: `STATE_FILE="${STATE_DIR}/tasks.json"`
- line 31: `WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"`

Current state artifacts:

- `tasks.json`
- `.tasks.lock`

Required design changes:

- keep `SCRIPT_DIR` for invoking sibling scripts only
- replace state root to `STATE_DIR="${WORKSPACE}/state"`
- keep `WORKSPACES_ROOT` for task workspace calculation if needed
- enforce workspace discovery order in command entrypoint

### 10.2 `monitor.sh`

Current path patterns:

- line 26: `SCRIPT_DIR=...`
- line 27: `WORKSPACE_ROOT="/home/node/.openclaw/workspaces/carpincho"`
- line 28: `STATE_DIR="${WORKSPACE_ROOT}/state"`
- line 29: `ALERTS_FILE="${STATE_DIR}/alerts.json"`
- line 30: `TASKS_FILE="${STATE_DIR}/tasks.json"`
- line 35: `HEALTH_STATE_FILE="${STATE_DIR}/.health_failures"`

Current state artifacts:

- `alerts.json`
- `tasks.json`
- `.health_failures`
- `.alerts.lock`

Required design changes:

- replace fixed `WORKSPACE_ROOT` with dynamic `WORKSPACE`
- set `STATE_DIR="${WORKSPACE}/state"`
- maintain `SCRIPT_DIR` only for child script dispatch (`task-manager`, `opencode-session`, `cleanup-workspace`)

### 10.3 `daemon-monitor.sh`

Current path patterns:

- line 8: `WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspaces/carpincho}"`
- line 9: `PIDFILE="$WORKSPACE/state/monitor-daemon.pid"`
- line 10: `LOGFILE="$WORKSPACE/state/monitor-daemon.log"`
- line 67: `bash "$WORKSPACE/scripts/monitor.sh"`
- line 78: `bash "$WORKSPACE/opencode-discord-pipe/watchdog-cron.sh"`
- line 89: `bash "$WORKSPACE/scripts/opencode-session-cleanup.sh"`
- line 96: `bash "$WORKSPACE/scripts/opencode-orphan-cleanup.sh"`

Current state artifacts:

- `monitor-daemon.pid`
- `monitor-daemon.log`

Required design changes:

- workspace default must follow discovery order env -> arg -> cwd
- child script invocations should use image scripts path (`SCRIPT_DIR` or fixed `/opt/scripts/orchestration`) not `$WORKSPACE/scripts`
- watchdog script path should be workspace-configurable if not image-baked

### 10.4 `opencode-session.sh`

Current path patterns:

- no `SCRIPT_DIR` coupling to mutable state
- line 200: `allowed_base="${WORKSPACES_ROOT:-/opt/opencode}"`

Current state artifacts:

- none local (API wrapper only)

Required design changes:

- keep mostly unchanged
- if path allowlist remains root-based, derive root from `WORKSPACE` when strict per-agent scoping is required
- preserve mention of `WORKSPACE` context injection in message payload

### 10.5 `setup-workspace.sh`

Current path patterns:

- line 25: `WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"`
- line 26: `REPOS_ROOT="${WORKSPACES_ROOT}/repos"`
- line 74: `WORKSPACE="${WORKSPACES_ROOT}/${TASK_ID}"`

Current hardcoded agent token:

- line 59: requires `GITHUB_TOKEN_carpincho`
- line 82: askpass emits `GITHUB_TOKEN_carpincho`
- line 183: writes `.git-token` from `GITHUB_TOKEN_carpincho`

State/config impacts:

- creates per-workspace helper files (`.git-token`, `.git-credential-helper.sh`, `.mise.toml`)

Required design changes:

- token resolution must use per-agent override + shared fallback
- preserve workspace-local credential helper mechanics
- no script-relative mutable path coupling present here

### 10.6 `github-pr.sh`

Current path patterns:

- line 33: `SCRIPT_DIR=...`
- line 54: uses `bash "$SCRIPT_DIR/task-manager.sh"`
- plan file reads from `"$workspace/.sisyphus/plans"`

Current hardcoded token pattern:

- line 35: `GITHUB_TOKEN="${GITHUB_TOKEN_carpincho:-}"`
- line 45: error references `GITHUB_TOKEN_carpincho`

Required design changes:

- keep `SCRIPT_DIR` for sibling script execution
- replace token resolution logic to generic per-agent form
- retain workspace-derived plan path behavior

### 10.7 `cleanup-workspace.sh`

Current path patterns:

- line 12: `WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"`
- line 13: `REPOS_ROOT="${WORKSPACES_ROOT}/repos"`
- line 33: `WORKSPACE="${WORKSPACES_ROOT}/${TASK_ID}"`

Current hardcoded token usage:

- line 117: checks `GITHUB_TOKEN_carpincho`
- line 127: uses `Authorization: token $GITHUB_TOKEN_carpincho`

Required design changes:

- token resolution generic per-agent
- keep workspace derivation from root/task-id unless interface redesigned
- no `SCRIPT_DIR/../state` issue in this script

### 10.8 `test-orchestrator.sh`

Current path patterns:

- line 4: `SCRIPTS="/home/node/.openclaw/workspaces/carpincho/scripts"`
- line 5: `WORKSPACE_ROOT="/home/node/.openclaw/workspaces/carpincho"`
- additional fixed references to that same path in assertions

Required design changes:

- convert to parameterized `WORKSPACE` and `SCRIPTS_DIR`
- avoid fixed absolute agent path assumptions
- update expected values to workspace-derived values

### 10.9 `test-approval-gate.sh`

Current path patterns:

- line 5: `SCRIPT_DIR=...`
- child script calls via `SCRIPT_DIR`

Required design changes:

- likely minimal path changes
- keep `SCRIPT_DIR` for sibling executable references
- no mutable state via script-relative paths found

### 10.10 `execute-task.sh`

Current path patterns:

- line 29: `SCRIPT_DIR=...`
- line 30: `WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"`
- line 31: `STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/../state}"`
- line 32: `LOCK_DIR="$STATE_DIR/locks"`

Required design changes:

- replace default state root with workspace-derived state
- keep `SCRIPT_DIR` for sibling script execution
- symlink path under `WORKSPACES_ROOT` remains design choice; ensure no cross-agent collisions

### 10.11 `gated-execute.sh`

Current path patterns:

- line 27: `SCRIPT_DIR=...`
- line 90: `WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"`
- line 91: symlink `.sisyphus` into shared root

Required design changes:

- preserve sibling script execution via `SCRIPT_DIR`
- ensure symlink strategy is safe in multi-agent concurrency (recommend workspace-local operation over shared mutable alias)

### 10.12 `opencode-orphan-cleanup.sh`

Current path patterns:

- no workspace path coupling
- API-only cleanup script

Required design changes:

- none for workspace state pathing
- optional: include `WORKSPACE` logging for observability consistency

### 10.13 `opencode-session-cleanup.sh`

Current path patterns:

- no workspace path coupling
- API-only cleanup script

Required design changes:

- none for workspace state pathing
- optional: include `WORKSPACE` logging for observability consistency

### 10.14 `render-plan-prompt.sh`

Current path patterns:

- line 27: `SCRIPT_DIR=...`
- line 28: `WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`
- line 29: `DEFAULT_TEMPLATE="${WORKSPACE_ROOT}/templates/plan-prompt.md"`

Required design changes:

- replace script-relative template root with workspace config root
- target default template: `${WORKSPACE}/config/templates/plan-prompt.md`
- keep `SCRIPT_DIR` for invoking `task-manager.sh`

## 11) Comprehensive Instance Table (Script, Line, Pattern, Replacement)

| Script | Line | Pattern | Replacement |
|---|---:|---|---|
| task-manager.sh | 29 | `STATE_DIR="${SCRIPT_DIR}/../state"` | `STATE_DIR="${WORKSPACE}/state"` |
| monitor.sh | 27 | `WORKSPACE_ROOT="/home/node/.openclaw/workspaces/carpincho"` | `WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"` |
| monitor.sh | 28 | `STATE_DIR="${WORKSPACE_ROOT}/state"` | `STATE_DIR="${WORKSPACE}/state"` |
| execute-task.sh | 31 | `STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/../state}"` | `STATE_DIR="${STATE_DIR:-${WORKSPACE}/state}"` |
| render-plan-prompt.sh | 28 | `WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"` | `WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"` |
| render-plan-prompt.sh | 29 | `DEFAULT_TEMPLATE="${WORKSPACE_ROOT}/templates/plan-prompt.md"` | `DEFAULT_TEMPLATE="${WORKSPACE}/config/templates/plan-prompt.md"` |
| test-orchestrator.sh | 4 | `SCRIPTS="/home/node/.openclaw/workspaces/carpincho/scripts"` | `SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/scripts/orchestration}"` |
| test-orchestrator.sh | 5 | `WORKSPACE_ROOT="/home/node/.openclaw/workspaces/carpincho"` | `WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"` |
| daemon-monitor.sh | 8 | `WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspaces/carpincho}"` | `WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"` |
| daemon-monitor.sh | 67 | `bash "$WORKSPACE/scripts/monitor.sh"` | `bash "${SCRIPTS_DIR:-/opt/scripts/orchestration}/monitor.sh"` |
| daemon-monitor.sh | 89 | `bash "$WORKSPACE/scripts/opencode-session-cleanup.sh"` | `bash "${SCRIPTS_DIR:-/opt/scripts/orchestration}/opencode-session-cleanup.sh"` |
| daemon-monitor.sh | 96 | `bash "$WORKSPACE/scripts/opencode-orphan-cleanup.sh"` | `bash "${SCRIPTS_DIR:-/opt/scripts/orchestration}/opencode-orphan-cleanup.sh"` |
| setup-workspace.sh | 59 | `GITHUB_TOKEN_carpincho` check | resolve via `TOKEN_VAR="GITHUB_TOKEN_${AGENT_ID}"` |
| setup-workspace.sh | 82 | askpass emits `GITHUB_TOKEN_carpincho` | askpass emits effective `GITHUB_TOKEN` |
| setup-workspace.sh | 183 | writes `.git-token` from `GITHUB_TOKEN_carpincho` | writes from resolved `GITHUB_TOKEN` |
| github-pr.sh | 35 | `GITHUB_TOKEN="${GITHUB_TOKEN_carpincho:-}"` | generic per-agent token resolution |
| github-pr.sh | 45 | error says `GITHUB_TOKEN_carpincho not set` | error says effective `GITHUB_TOKEN` missing |
| cleanup-workspace.sh | 117 | checks `GITHUB_TOKEN_carpincho` | checks effective token from agent override fallback |
| cleanup-workspace.sh | 127 | `Authorization: token $GITHUB_TOKEN_carpincho` | `Authorization: token $GITHUB_TOKEN` |
| monitor.sh | 29 | `ALERTS_FILE="${STATE_DIR}/alerts.json"` | unchanged file name under workspace state |
| monitor.sh | 30 | `TASKS_FILE="${STATE_DIR}/tasks.json"` | unchanged file name under workspace state |
| monitor.sh | 35 | `HEALTH_STATE_FILE="${STATE_DIR}/.health_failures"` | unchanged file name under workspace state |
| daemon-monitor.sh | 9 | `PIDFILE="$WORKSPACE/state/monitor-daemon.pid"` | unchanged name, dynamic workspace |
| daemon-monitor.sh | 10 | `LOGFILE="$WORKSPACE/state/monitor-daemon.log"` | unchanged name, dynamic workspace |
| execute-task.sh | 32 | `LOCK_DIR="$STATE_DIR/locks"` | unchanged structure under workspace state |
| task-manager.sh | 30 | `STATE_FILE="${STATE_DIR}/tasks.json"` | unchanged file name under workspace state |

## 12) SCRIPT_DIR Audit: Keep vs Replace

### Keep `SCRIPT_DIR`

`SCRIPT_DIR` is still valid for executable script dispatch:

- `task-manager.sh` invoking peer scripts
- `monitor.sh` invoking `task-manager.sh` / `opencode-session.sh` / `cleanup-workspace.sh`
- `github-pr.sh` invoking `task-manager.sh`
- `execute-task.sh` invoking `task-manager.sh` / `opencode-session.sh` / `gated-execute.sh`
- `gated-execute.sh` invoking peer scripts
- `test-approval-gate.sh` invoking peer scripts

### Replace `SCRIPT_DIR`

Any usage where `SCRIPT_DIR` anchors mutable data must be replaced:

- `task-manager.sh` state dir
- `execute-task.sh` default state dir
- any future `SCRIPT_DIR/../config` or `SCRIPT_DIR/../templates` pattern

## 13) Workspace Discovery Pseudocode

```bash
resolve_workspace() {
  local arg_workspace="${1:-}"
  local ws="${WORKSPACE:-${arg_workspace:-$(pwd)}}"

  if [ -z "$ws" ]; then
    echo "ERROR: WORKSPACE resolution failed" >&2
    return 1
  fi

  case "$ws" in
    /*) ;;
    *)
      ws="$(cd "$ws" 2>/dev/null && pwd)" || {
        echo "ERROR: WORKSPACE must be absolute or resolvable" >&2
        return 1
      }
      ;;
  esac

  echo "$ws"
}
```

## 14) Token Resolution Pseudocode

```bash
resolve_github_token() {
  AGENT_ID="${AGENT_ID:-default}"
  TOKEN_VAR="GITHUB_TOKEN_${AGENT_ID}"
  GITHUB_TOKEN="${!TOKEN_VAR:-$GITHUB_TOKEN}"

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "ERROR: missing GitHub token; expected ${TOKEN_VAR} or GITHUB_TOKEN" >&2
    return 1
  fi

  export GITHUB_TOKEN
}
```

## 15) Per-Agent State and Config Contract

### Mandatory directories

- `"$WORKSPACE/state"`
- `"$WORKSPACE/state/locks"`
- `"$WORKSPACE/config"`
- `"$WORKSPACE/config/templates"`
- `"$WORKSPACE/config/repo-configs"`

### Mandatory files (on demand creation)

- `"$WORKSPACE/state/tasks.json"`
- `"$WORKSPACE/state/alerts.json"`
- `"$WORKSPACE/state/.health_failures"`

### Optional files

- `"$WORKSPACE/state/monitor-daemon.pid"`
- `"$WORKSPACE/state/monitor-daemon.log"`

## 16) Migration Guidance by Script Group

### Group A: State-coupled scripts

- `task-manager.sh`
- `monitor.sh`
- `execute-task.sh`
- `daemon-monitor.sh`

Action focus:

- workspace discovery bootstrap
- state path replacement
- lock/pid/log relocation under workspace

### Group B: Token-coupled scripts

- `setup-workspace.sh`
- `github-pr.sh`
- `cleanup-workspace.sh`

Action focus:

- per-agent token override fallback
- remove hardcoded `carpincho` token naming

### Group C: Test harnesses with hardcoded paths

- `test-orchestrator.sh`

Action focus:

- path parameterization for scripts and workspace

### Group D: Mostly compliant scripts

- `opencode-session.sh`
- `test-approval-gate.sh`
- `gated-execute.sh`
- `opencode-orphan-cleanup.sh`
- `opencode-session-cleanup.sh`

Action focus:

- consistency hardening
- avoid implicit single-agent assumptions

### Group E: Template/config anchor script

- `render-plan-prompt.sh`

Action focus:

- template root move to `$WORKSPACE/config/templates`

## 17) Risk Notes and Mitigations

### Risk: Shared `.sisyphus` symlink collisions

Observed in:

- `execute-task.sh` line 167
- `gated-execute.sh` line 91

Issue:

- writing `"$WORKSPACES_ROOT/.sisyphus"` may collide if multiple tasks run concurrently

Mitigation direction:

- avoid shared mutable global symlink
- prefer passing explicit workspace to commands that need `.sisyphus`

### Risk: daemon script assumes script copies in workspace

Observed in:

- `daemon-monitor.sh` script dispatch to `$WORKSPACE/scripts/...`

Issue:

- image-baked strategy expects scripts in `/opt/scripts/orchestration/`

Mitigation direction:

- centralize script binary location via `SCRIPTS_DIR`

### Risk: token env naming drift

Issue:

- coexistence of legacy and new token names can create confusion

Mitigation direction:

- define one canonical precedence and enforce logs/errors accordingly

## 18) Implementation Checklist for Task 4 (Refactor Task)

1. Introduce `resolve_workspace` helper in scripts needing mutable paths.
2. Replace every `SCRIPT_DIR/../state` derivation with `$WORKSPACE/state`.
3. Replace fixed `carpincho` workspace paths with dynamic `WORKSPACE` resolution.
4. Keep `SCRIPT_DIR` only for sibling executable invocation.
5. Introduce token resolution helper using `AGENT_ID` + indirect expansion.
6. Replace all `GITHUB_TOKEN_carpincho` usage points.
7. Introduce/normalize `SCRIPTS_DIR` for scripts executed from daemon/test harness.
8. Move template/config defaults to `$WORKSPACE/config/...`.
9. Ensure directory creation for `state/` and `config/` where required.
10. Update tests to avoid hardcoded `/home/node/.openclaw/workspaces/carpincho` assumptions.
11. Validate concurrency safety around `.sisyphus` shared symlink behavior.
12. Validate all scripts run with env var only (`WORKSPACE`) and with arg fallback.
13. Validate `WORKSPACE` env unset mode uses `$1` then `pwd`.
14. Validate token fallback behavior for both override and shared token cases.
15. Validate no script writes mutable artifacts below `/opt/scripts/orchestration/`.

## 19) Verification Targets (for this design doc)

Expected grep checks:

- `WORKSPACE` appears at least 10 times
- `SCRIPT_DIR` appears at least 5 times
- key script names appear repeatedly (`task-manager`, `monitor`, `opencode-session`, `github-pr`)

## 20) Reference Snippets (normative)

### Workspace/state bootstrap snippet

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
STATE_DIR="${WORKSPACE}/state"
mkdir -p "${STATE_DIR}" "${WORKSPACE}/config"
```

### Token bootstrap snippet

```bash
AGENT_ID="${AGENT_ID:-default}"
TOKEN_VAR="GITHUB_TOKEN_${AGENT_ID}"
GITHUB_TOKEN="${!TOKEN_VAR:-$GITHUB_TOKEN}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: missing GitHub token; expected ${TOKEN_VAR} or GITHUB_TOKEN" >&2
  exit 1
fi
```

### Script dispatch snippet

```bash
SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/scripts/orchestration}"
bash "${SCRIPTS_DIR}/task-manager.sh" list --active
bash "${SCRIPTS_DIR}/monitor.sh" all
bash "${SCRIPTS_DIR}/opencode-session.sh" list
bash "${SCRIPTS_DIR}/github-pr.sh" check "${TASK_ID}"
```

## 21) Appendix A - Full 14-Script Coverage Matrix

| Script | Has SCRIPT_DIR | Has SCRIPT_DIR/../ | Has hardcoded workspace path | Has token coupling | Writes state files | Needs refactor |
|---|---|---|---|---|---|---|
| task-manager.sh | yes | yes | no | no | yes | yes |
| monitor.sh | yes | no | yes | no | yes | yes |
| daemon-monitor.sh | no | no | default hardcoded path | no | yes | yes |
| opencode-session.sh | no | no | no fixed single-agent path | no | no | low |
| setup-workspace.sh | helper-only | no | no | yes | workspace files only | yes |
| github-pr.sh | yes | no | no | yes | no | yes |
| cleanup-workspace.sh | no | no | no | yes | no | yes |
| test-orchestrator.sh | no | no | yes | no | touches state in tests | yes |
| test-approval-gate.sh | yes | no | no | no | no | low |
| execute-task.sh | yes | yes | no | no | lock files | yes |
| gated-execute.sh | yes | no | no | no | no | medium |
| opencode-orphan-cleanup.sh | no | no | no | no | no | none |
| opencode-session-cleanup.sh | no | no | no | no | no | none |
| render-plan-prompt.sh | yes | parent-root | no | no | no | yes |

## 22) Appendix B - Script Name Canonical Mentions

Key scripts for orchestration contract:

- `task-manager.sh`
- `monitor.sh`
- `opencode-session.sh`
- `github-pr.sh`

These scripts are central for state lifecycle, deterministic health checks, OpenCode session control, and PR gating.

Re-mention for implementation indexing:

- task-manager
- monitor
- opencode-session
- github-pr
- task-manager
- monitor
- opencode-session
- github-pr

## 23) Final Design Decisions

1. Workspace resolution is explicit and runtime-driven, never inferred from script install location.
2. `SCRIPT_DIR` is retained only for dispatching sibling scripts in `/opt/scripts/orchestration/`.
3. Mutable state and config are strictly workspace-local.
4. Token resolution is per-agent override first, shared fallback second.
5. Test harnesses must be path-parameterized; no fixed agent path assumptions.
6. Legacy `GITHUB_TOKEN_carpincho` is migration-only and not part of target contract.

## 24) Ready-for-Implementation Criteria

Task 4 implementer can proceed when:

- each target script has explicit workspace bootstrap
- each state path is workspace-local
- each token lookup follows per-agent override fallback
- template/config roots are workspace config roots
- all hardcoded Carpincho workspace paths are removed
- validation confirms no mutable writes under `/opt/scripts/orchestration/`

