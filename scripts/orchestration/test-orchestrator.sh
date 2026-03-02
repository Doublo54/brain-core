#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
set -uo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/scripts/orchestration}"
SCRIPTS="$SCRIPTS_DIR"
WORKSPACE="${WORKSPACE:-${1:-$(pwd)}}"
PASS=0
FAIL=0
TOTAL=0

# Generate valid task IDs matching task-{timestamp}-{hex} format
_TS=$(date +%s)
TID1="task-${_TS}-a0000001"
TID2="task-${_TS}-a0000002"
TID_MON="task-${_TS}-a0000003"
TID_DUP="task-${_TS}-a0000004"
TID_NOPR="task-${_TS}-a0000005"

test_result() {
  TOTAL=$((TOTAL + 1))
  if [ "$1" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $2"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $2"
  fi
}

echo "=== 1. TASK MANAGER ==="

# 1.1 Create task
echo "[1.1] Create task"
OUT=$(bash "$SCRIPTS/task-manager.sh" create "$TID1" "example-org/example-repo" "Test task for PR8 validation" --base-branch main 2>/dev/null)
echo "$OUT" | TID="$TID1" python3 -c "import sys,json,os; t=json.load(sys.stdin); tid=os.environ['TID']; assert t['id']==tid; assert t['status']=='created'" 2>/dev/null
test_result $? "Create task with valid args"

# 1.2 Get task
echo "[1.2] Get task"
OUT=$(bash "$SCRIPTS/task-manager.sh" get "$TID1" 2>/dev/null)
echo "$OUT" | TID="$TID1" python3 -c "import sys,json,os; t=json.load(sys.stdin); tid=os.environ['TID']; assert t['id']==tid; assert t['workspace']==f'/opt/opencode/{tid}'" 2>/dev/null
test_result $? "Get task returns correct data"

# 1.3 Status transition (follows Phase 9 approval gate flow)
echo "[1.3] Status transitions"
bash "$SCRIPTS/task-manager.sh" status "$TID1" "planning" >/dev/null 2>&1
test_result $? "created → planning"

bash "$SCRIPTS/task-manager.sh" status "$TID1" "plan_review" >/dev/null 2>&1
test_result $? "planning → plan_review"

bash "$SCRIPTS/task-manager.sh" status "$TID1" "approved" >/dev/null 2>&1
test_result $? "plan_review → approved"

bash "$SCRIPTS/task-manager.sh" status "$TID1" "executing" >/dev/null 2>&1
test_result $? "approved → executing"

bash "$SCRIPTS/task-manager.sh" status "$TID1" "validating" >/dev/null 2>&1
test_result $? "executing → validating"

bash "$SCRIPTS/task-manager.sh" status "$TID1" "code_review" >/dev/null 2>&1
test_result $? "validating → code_review"

bash "$SCRIPTS/task-manager.sh" status "$TID1" "completed" >/dev/null 2>&1
test_result $? "code_review → completed"

# 1.4 Terminal status block (TOCTOU fix - F4)
echo "[1.4] Terminal status block"
bash "$SCRIPTS/task-manager.sh" status "$TID1" "planning" >/dev/null 2>&1
BLOCKED=$?
[ "$BLOCKED" -ne 0 ]
test_result $? "Cannot transition from terminal status (exit $BLOCKED)"

# 1.5 Update field
echo "[1.5] Update field"
bash "$SCRIPTS/task-manager.sh" create "$TID2" "example-org/example-repo" "Update test" 2>/dev/null >/dev/null
bash "$SCRIPTS/task-manager.sh" update "$TID2" "session_id" "ses_test123" >/dev/null 2>&1
OUT=$(bash "$SCRIPTS/task-manager.sh" get "$TID2" 2>/dev/null)
echo "$OUT" | python3 -c "import sys,json; t=json.load(sys.stdin); assert t['session_id']=='ses_test123'" 2>/dev/null
test_result $? "Update session_id field"

# 1.6 List active
echo "[1.6] List active"
OUT=$(bash "$SCRIPTS/task-manager.sh" list --active 2>/dev/null)
echo "$OUT" | TID1="$TID1" TID2="$TID2" python3 -c "import sys,json,os; tasks=json.load(sys.stdin); ids=[t['id'] for t in tasks]; assert os.environ['TID2'] in ids; assert os.environ['TID1'] not in ids" 2>/dev/null
test_result $? "List --active excludes terminal tasks"

# 1.7 Invalid task-id
echo "[1.7] Input validation"
bash "$SCRIPTS/task-manager.sh" create "../traversal" "example-org/example-repo" "bad" 2>/dev/null >/dev/null
[ $? -ne 0 ]
test_result $? "Reject path traversal task-id"

bash "$SCRIPTS/task-manager.sh" create "valid-id" "not-a-repo" "bad" 2>/dev/null >/dev/null
[ $? -ne 0 ]
test_result $? "Reject invalid repo format"

# 1.8 Delete
echo "[1.8] Delete"
bash "$SCRIPTS/task-manager.sh" delete "$TID1" >/dev/null 2>&1
test_result $? "Delete completed task"
bash "$SCRIPTS/task-manager.sh" delete "$TID2" >/dev/null 2>&1
test_result $? "Delete active task"

echo ""
echo "=== 2. OPENCODE SESSION ==="

# 2.1 List sessions
echo "[2.1] List sessions"
OUT=$(bash "$SCRIPTS/opencode-session.sh" list 2>/dev/null)
echo "$OUT" | python3 -c "import sys,json; s=json.load(sys.stdin); assert isinstance(s, list)" 2>/dev/null
test_result $? "List sessions returns array"

# 2.2 Create session
echo "[2.2] Create session"
SID=$(bash "$SCRIPTS/opencode-session.sh" create 2>/dev/null)
[ -n "$SID" ] && [[ "$SID" == ses_* ]]
test_result $? "Create session (got: ${SID:-empty})"

# 2.3 Send message
echo "[2.3] Send message"
if [ -n "$SID" ]; then
  echo "What is 1+1? Reply with just the number." > /tmp/test-msg.txt
  OUT=$(bash "$SCRIPTS/opencode-session.sh" send "$SID" /tmp/test-msg.txt 2>/dev/null)
  test_result $? "Send message to session"
  rm -f /tmp/test-msg.txt
else
  test_result 1 "Send message (skipped — no session)"
fi

# 2.4 Status check
echo "[2.4] Session status"
if [ -n "$SID" ]; then
  OUT=$(bash "$SCRIPTS/opencode-session.sh" status "$SID" 2>/dev/null)
  echo "$OUT" | python3 -c "import sys,json; s=json.load(sys.stdin); assert 'id' in s" 2>/dev/null
  test_result $? "Session status returns valid JSON"
else
  test_result 1 "Session status (skipped)"
fi

# 2.5 Delete session
echo "[2.5] Delete session"
if [ -n "$SID" ]; then
  bash "$SCRIPTS/opencode-session.sh" delete "$SID" >/dev/null 2>&1
  test_result $? "Delete session"
else
  test_result 1 "Delete session (skipped)"
fi

# 2.6 Invalid session ID
echo "[2.6] Input validation"
bash "$SCRIPTS/opencode-session.sh" status "../bad" >/dev/null 2>&1
[ $? -ne 0 ]
test_result $? "Reject invalid session-id"

echo ""
echo "=== 3. WORKSPACE SETUP + CLEANUP ==="

# 3.1 Setup workspace (requires GITHUB_TOKEN and network access)
echo "[3.1] Setup workspace"
TEST_REPO_OWNER="${TEST_REPO_OWNER:-example-org}"
TEST_REPO_URL="https://github.com/${TEST_REPO_OWNER}/brain"
OUT=$(bash "$SCRIPTS/setup-workspace.sh" "test-pr8-ws" "$TEST_REPO_URL" "main" 2>/dev/null)
SETUP_EXIT=$?
test_result $SETUP_EXIT "Setup workspace for brain-core repo"

if [ $SETUP_EXIT -eq 0 ]; then
  # 3.2 Verify workspace structure
  echo "[3.2] Workspace structure"
  WS="/opt/opencode/test-pr8-ws"
  [ -d "$WS" ] && [ -f "$WS/.git" ] && [ -f "$WS/.mise.toml" ]
  test_result $? "Workspace dir + .git + .mise.toml exist"

  # 3.3 Credential helper (B3 fix)
  echo "[3.3] Credential helper"
  [ -f "$WS/.git-credential-helper.sh" ] && [ -f "$WS/.git-token" ] && [ -x "$WS/.git-credential-helper.sh" ]
  test_result $? "Credential helper + token file exist and executable"

  # 3.4 Token not in git config (F6 fix — no token in clone URL)
  echo "[3.4] Token not in remote URL"
  REMOTE=$(git -C "$WS" remote get-url origin 2>/dev/null)
  echo "$REMOTE" | grep -qv "x-access-token"
  test_result $? "Remote URL has no embedded token ($REMOTE)"

  # 3.5 WORKSPACES_ROOT override (F3 fix)
  echo "[3.5] WORKSPACES_ROOT consistency"
  grep -q 'WORKSPACES_ROOT="${WORKSPACES_ROOT:-' "$SCRIPTS/setup-workspace.sh"
  test_result $? "setup-workspace.sh uses overridable WORKSPACES_ROOT"

  # 3.6 .gitignore entries
  echo "[3.6] .gitignore coverage"
  grep -qF ".git-token" "$WS/.gitignore" && grep -qF ".git-credential-helper.sh" "$WS/.gitignore"
  test_result $? ".gitignore covers credential files"

  # 3.7 Cleanup
  echo "[3.7] Cleanup workspace"
  bash "$SCRIPTS/cleanup-workspace.sh" "test-pr8-ws" --delete-branch 2>/dev/null
  [ ! -d "$WS" ]
  test_result $? "Workspace removed after cleanup"

  # 3.8 Credential files gone
  echo "[3.8] Credentials cleaned"
  [ ! -f "$WS/.git-token" ] && [ ! -f "$WS/.git-credential-helper.sh" ]
  test_result $? "Credential files removed"
else
  for i in $(seq 2 8); do
    test_result 1 "3.$i (skipped — setup failed)"
  done
fi

echo ""
echo "=== 4. SOURCE FILE CHECKS ==="

PIPE_DIR="/opt/integrations/opencode-discord-pipe"

echo "[4.1] No npx in start.sh (executable calls only)"
NPX_EXEC=$(sed 's/#.*$//' "$PIPE_DIR/start.sh" | grep -E '\bnpx\b' || true)
[ -z "$NPX_EXEC" ]
test_result $? "No executable npx in start.sh (F7)"

echo "[4.2] No TEST_COMMANDS placeholder in config template"
if [ -f "$WORKSPACE/config/templates/plan-prompt.md" ]; then
  grep -q "TEST_COMMANDS" "$WORKSPACE/config/templates/plan-prompt.md"
  TC_FOUND=$?
  [ $TC_FOUND -ne 0 ]
  test_result $? "No TEST_COMMANDS in plan-prompt.md (F5)"
else
  test_result 0 "No TEST_COMMANDS in plan-prompt.md (template not present in image — repo-level check)"
fi

echo ""
echo "=== 5. MONITOR ==="

# 5.0 Usage
echo "[5.0] Monitor usage"
bash "$SCRIPTS/monitor.sh" badcmd 2>/dev/null
[ $? -eq 1 ]
test_result $? "Invalid subcommand → exit 1"

# 5.1 Health check
echo "[5.1] OpenCode health"
OUT=$(WORKSPACE="$WORKSPACE" bash "$SCRIPTS/monitor.sh" health 2>/dev/null)
echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['opencode_health_failures'] == 0" 2>/dev/null
test_result $? "Health check passes (OpenCode running)"

# 5.2 Full run with no tasks
echo "[5.2] Full run (no tasks)"
OUT=$(WORKSPACE="$WORKSPACE" bash "$SCRIPTS/monitor.sh" all 2>/dev/null)
echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['status'] == 'healthy'; assert d['active_tasks'] == 0" 2>/dev/null
test_result $? "Full run reports healthy with 0 tasks"

# 5.3 Timeout detection
echo "[5.3] Timeout detection"
bash "$SCRIPTS/task-manager.sh" create "$TID_MON" "example-org/example-brain" "timeout test" 2>/dev/null >/dev/null
bash "$SCRIPTS/task-manager.sh" status "$TID_MON" "planning" 2>/dev/null >/dev/null
bash "$SCRIPTS/task-manager.sh" update "$TID_MON" "phase_started_at" "2026-01-01T00:00:00+00:00" 2>/dev/null >/dev/null
bash "$SCRIPTS/task-manager.sh" update "$TID_MON" "created_at" "2026-01-01T00:00:00+00:00" 2>/dev/null >/dev/null
WORKSPACE="$WORKSPACE" bash "$SCRIPTS/monitor.sh" tasks >/dev/null 2>&1
TASK_STATUS=$(bash "$SCRIPTS/task-manager.sh" get "$TID_MON" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null)
[ "$TASK_STATUS" = "timed_out" ]
test_result $? "Timed-out task marked as timed_out (got: $TASK_STATUS)"

# 5.4 Alert written
echo "[5.4] Alert written"
ALERT_COUNT=$(python3 -c "
import json
with open('$WORKSPACE/state/alerts.json') as f:
    data = json.load(f)
unresolved = [a for a in data['alerts'] if not a.get('resolved_at')]
print(len(unresolved))
" 2>/dev/null)
[ "$ALERT_COUNT" -gt 0 ]
test_result $? "Alert exists for timed-out task ($ALERT_COUNT unresolved)"

# 5.5 Alert deduplication
echo "[5.5] Alert deduplication"
BEFORE=$ALERT_COUNT
WORKSPACE="$WORKSPACE" bash "$SCRIPTS/monitor.sh" tasks >/dev/null 2>&1
AFTER=$(python3 -c "
import json
with open('$WORKSPACE/state/alerts.json') as f:
    data = json.load(f)
unresolved = [a for a in data['alerts'] if not a.get('resolved_at')]
print(len(unresolved))
" 2>/dev/null)
[ "$BEFORE" = "$AFTER" ]
test_result $? "No duplicate alert on re-run ($BEFORE → $AFTER)"

# Cleanup
bash "$SCRIPTS/task-manager.sh" delete "$TID_MON" >/dev/null 2>&1
echo '{"alerts": [], "version": 1}' > "$WORKSPACE/state/alerts.json"

echo ""
echo "=== 6. GITHUB PR SCRIPT ==="

# 6.1 Usage validation
echo "[6.1] Usage validation"
bash "$SCRIPTS/github-pr.sh" 2>/dev/null
[ $? -eq 1 ]
test_result $? "No args → exit 1"

bash "$SCRIPTS/github-pr.sh" create 2>/dev/null
[ $? -eq 1 ]
test_result $? "create without task-id → exit 1"

bash "$SCRIPTS/github-pr.sh" badcmd 2>/dev/null
[ $? -eq 1 ]
test_result $? "Unknown command → exit 1"

# 6.2 Task not found
echo "[6.2] Task not found"
bash "$SCRIPTS/github-pr.sh" create "nonexistent-task" 2>/dev/null
[ $? -eq 2 ]
test_result $? "create with missing task → exit 2"

bash "$SCRIPTS/github-pr.sh" check "nonexistent-task" 2>/dev/null
[ $? -eq 2 ]
test_result $? "check with missing task → exit 2"

bash "$SCRIPTS/github-pr.sh" comment "nonexistent-task" "test" 2>/dev/null
[ $? -eq 2 ]
test_result $? "comment with missing task → exit 2"

bash "$SCRIPTS/github-pr.sh" ready "nonexistent-task" 2>/dev/null
[ $? -eq 2 ]
test_result $? "ready with missing task → exit 2"

# 6.3 Duplicate PR guard
echo "[6.3] Duplicate PR guard"
bash "$SCRIPTS/task-manager.sh" create "$TID_DUP" "example-org/example-brain" "dup test" 2>/dev/null >/dev/null
bash "$SCRIPTS/task-manager.sh" update "$TID_DUP" pr_number "999" 2>/dev/null >/dev/null
bash "$SCRIPTS/github-pr.sh" create "$TID_DUP" 2>/dev/null
[ $? -eq 5 ]
test_result $? "create rejects when PR already exists → exit 5"
bash "$SCRIPTS/task-manager.sh" delete "$TID_DUP" >/dev/null 2>&1

# 6.4 No PR check/comment/ready
echo "[6.4] Missing PR number"
bash "$SCRIPTS/task-manager.sh" create "$TID_NOPR" "example-org/example-brain" "no PR test" 2>/dev/null >/dev/null
bash "$SCRIPTS/github-pr.sh" check "$TID_NOPR" 2>/dev/null
[ $? -eq 2 ]
test_result $? "check rejects task without PR → exit 2"

bash "$SCRIPTS/github-pr.sh" comment "$TID_NOPR" "test" 2>/dev/null
[ $? -eq 2 ]
test_result $? "comment rejects task without PR → exit 2"

bash "$SCRIPTS/github-pr.sh" ready "$TID_NOPR" 2>/dev/null
[ $? -eq 2 ]
test_result $? "ready rejects task without PR → exit 2"
bash "$SCRIPTS/task-manager.sh" delete "$TID_NOPR" >/dev/null 2>&1

echo ""
echo "=== 7. TEMPLATE RENDERER ==="

# Generate valid task ID
TEST_RENDER_ID="task-$(date +%s)-$(openssl rand -hex 4)"

# Create a mock template with required critical sections
MOCK_TEMPLATE="/tmp/test-plan-template.md"
cat > "$MOCK_TEMPLATE" <<'TMPL'
# Plan for {{TASK_ID}}

Repo: {{REPO_NAME}} Branch: {{BASE_BRANCH}} Workspace: {{WORKSPACE}}

## Communication
NEVER use the question tool during execution.

## Commit Rules
Always use conventional commits.

## Task
{{TASK_DESCRIPTION}}
TMPL

# 7.1 Successful render
echo "[7.1] Successful rendering"
bash "$SCRIPTS/task-manager.sh" create "$TEST_RENDER_ID" "example-org/example-brain" "Test render task" --base-branch main >/dev/null 2>&1
WORKSPACE="$WORKSPACE" bash "$SCRIPTS/render-plan-prompt.sh" "$TEST_RENDER_ID" "/tmp/test-render-ok.md" "$MOCK_TEMPLATE" >/dev/null 2>&1
test_result $? "Render with valid task succeeds"

# 7.2 Critical sections present
echo "[7.2] Critical sections validation"
grep -q "## Communication" /tmp/test-render-ok.md && \
grep -q "NEVER use the question tool" /tmp/test-render-ok.md && \
grep -q "## Commit Rules" /tmp/test-render-ok.md
test_result $? "All critical sections present in output"

# 7.3 Variable substitution
echo "[7.3] Variable substitution"
grep -q "$TEST_RENDER_ID" /tmp/test-render-ok.md && \
grep -q "brain" /tmp/test-render-ok.md && \
grep -q "main" /tmp/test-render-ok.md
test_result $? "Task ID, repo, and branch substituted correctly"

# 7.4 Bad template fails validation
echo "[7.4] Bad template validation"
echo "Bad template without critical sections" > /tmp/bad-template.md
WORKSPACE="$WORKSPACE" bash "$SCRIPTS/render-plan-prompt.sh" "$TEST_RENDER_ID" "/tmp/test-render-fail.md" "/tmp/bad-template.md" >/dev/null 2>&1
[ $? -eq 4 ]
test_result $? "Missing critical sections → exit 4"

# 7.5 Atomic write (no partial file on failure)
echo "[7.5] Atomic write on failure"
[ ! -f "/tmp/test-render-fail.md" ]
test_result $? "Failed render does not create output file"

# 7.6 Nonexistent task
echo "[7.6] Nonexistent task"
WORKSPACE="$WORKSPACE" bash "$SCRIPTS/render-plan-prompt.sh" "task-9999999999-ffffffff" "/tmp/test-render-noent.md" "$MOCK_TEMPLATE" >/dev/null 2>&1
[ $? -eq 2 ]
test_result $? "Nonexistent task → exit 2"

# Cleanup
bash "$SCRIPTS/task-manager.sh" delete "$TEST_RENDER_ID" >/dev/null 2>&1
rm -f /tmp/test-render-ok.md /tmp/bad-template.md "$MOCK_TEMPLATE"

echo ""
echo "================================"
echo "RESULTS: $PASS/$TOTAL passed, $FAIL failed"
echo "================================"
