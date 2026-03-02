#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# test-approval-gate.sh — Integration tests for Gateway approval enforcement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }

log_test() {
  TEST_COUNT=$((TEST_COUNT + 1))
  echo -e "\n[$TEST_COUNT] $*"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  green "  ✓ PASS"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  red "  ✗ FAIL: $*"
}

cleanup_test_task() {
  local task_id="$1"
  bash "$SCRIPT_DIR/task-manager.sh" delete "$task_id" >/dev/null 2>&1 || true
}

echo "================================================"
echo "Gateway Approval Gate Integration Tests"
echo "================================================"

# --- Test 1: Invalid task ID format rejection ---
log_test "execute-task.sh rejects invalid task ID format"
OUTPUT=$(bash "$SCRIPT_DIR/execute-task.sh" "invalid-id" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "invalid task id"; then
  pass
else
  fail "Should reject task ID without proper format. Got: $OUTPUT"
fi

log_test "execute-task.sh rejects path traversal attempts"
OUTPUT=$(bash "$SCRIPT_DIR/execute-task.sh" "../../../etc/passwd" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "invalid task id"; then
  pass
else
  fail "Should reject path traversal attempt. Got: $OUTPUT"
fi

log_test "gated-execute.sh requires all arguments"
OUTPUT=$(bash "$SCRIPT_DIR/gated-execute.sh" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "missing required"; then
  pass
else
  fail "Should require task-id, workspace, and session-id. Got: $OUTPUT"
fi

log_test "gated-execute.sh validates task ID format"
OUTPUT=$(bash "$SCRIPT_DIR/gated-execute.sh" "bad-id" "/tmp" "session-123" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "invalid task id"; then
  pass
else
  fail "Should validate task ID format. Got: $OUTPUT"
fi

log_test "gated-execute.sh validates workspace exists"
OUTPUT=$(bash "$SCRIPT_DIR/gated-execute.sh" "task-1234567890-abcd1234" "/nonexistent/path" "session-123" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "workspace not found"; then
  pass
else
  fail "Should reject nonexistent workspace. Got: $OUTPUT"
fi

# --- Test 6: task-manager.sh creates task with auto_approve field ---
log_test "task-manager.sh creates task with auto_approve=false by default"
TEST_TASK="task-$(date +%s)-$(printf '%08x' $RANDOM)"
bash "$SCRIPT_DIR/task-manager.sh" create "$TEST_TASK" "test/repo" "Test task" >/dev/null 2>&1
AUTO_APPROVE=$(bash "$SCRIPT_DIR/task-manager.sh" get "$TEST_TASK" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('auto_approve', 'MISSING'))")
if [ "$AUTO_APPROVE" = "False" ]; then
  pass
else
  fail "auto_approve should default to False, got: $AUTO_APPROVE"
fi
cleanup_test_task "$TEST_TASK"

# --- Test 7: task-manager.sh blocks auto_approve updates (security) ---
log_test "task-manager.sh blocks auto_approve updates via update command"
TEST_TASK="task-$(date +%s)-$(printf '%08x' $RANDOM)"
bash "$SCRIPT_DIR/task-manager.sh" create "$TEST_TASK" "test/repo" "Test task" >/dev/null 2>&1
OUTPUT=$(bash "$SCRIPT_DIR/task-manager.sh" update "$TEST_TASK" auto_approve true 2>&1 || true)
if echo "$OUTPUT" | grep -qi "protected"; then
  pass
else
  fail "auto_approve should be protected field. Got: $OUTPUT"
fi
cleanup_test_task "$TEST_TASK"

# --- Test 8: State machine has 'approved' status ---
log_test "task-manager.sh accepts 'approved' status"
TEST_TASK="task-$(date +%s)-$(printf '%08x' $RANDOM)"
bash "$SCRIPT_DIR/task-manager.sh" create "$TEST_TASK" "test/repo" "Test task" >/dev/null 2>&1
bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" planning --force >/dev/null 2>&1
bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" plan_review --force >/dev/null 2>&1
if bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" approved 2>&1 | grep -q '"status": "approved"'; then
  pass
else
  fail "Should accept transition to 'approved' status"
fi
cleanup_test_task "$TEST_TASK"

# --- Test 9: State machine has 'blocked' status ---
log_test "task-manager.sh accepts 'blocked' status"
TEST_TASK="task-$(date +%s)-$(printf '%08x' $RANDOM)"
bash "$SCRIPT_DIR/task-manager.sh" create "$TEST_TASK" "test/repo" "Test task" >/dev/null 2>&1
bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" planning --force >/dev/null 2>&1
if bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" blocked 2>&1 | grep -q '"status": "blocked"'; then
  pass
else
  fail "Should accept transition to 'blocked' status"
fi
cleanup_test_task "$TEST_TASK"

log_test "task-manager.sh blocks invalid state transitions"
TEST_TASK="task-$(date +%s)-$(printf '%08x' $RANDOM)"
bash "$SCRIPT_DIR/task-manager.sh" create "$TEST_TASK" "test/repo" "Test task" >/dev/null 2>&1
OUTPUT=$(bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" executing 2>&1 || true)
if echo "$OUTPUT" | grep -qi "invalid transition"; then
  pass
else
  fail "Should block direct created->executing transition. Got: $OUTPUT"
fi
cleanup_test_task "$TEST_TASK"

log_test "execute-task.sh rejects task not in 'approved' state"
TEST_TASK="task-$(date +%s)-$(printf '%08x' $RANDOM)"
bash "$SCRIPT_DIR/task-manager.sh" create "$TEST_TASK" "test/repo" "Test task" >/dev/null 2>&1
bash "$SCRIPT_DIR/task-manager.sh" status "$TEST_TASK" planning --force >/dev/null 2>&1
OUTPUT=$(bash "$SCRIPT_DIR/execute-task.sh" "$TEST_TASK" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "not 'approved'\|not approved"; then
  pass
else
  fail "Should reject task not in approved state. Got: $OUTPUT"
fi
cleanup_test_task "$TEST_TASK"

log_test "execute-task.sh rejects nonexistent task"
OUTPUT=$(bash "$SCRIPT_DIR/execute-task.sh" "task-9999999999-deadbeef" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "not found"; then
  pass
else
  fail "Should reject nonexistent task. Got: $OUTPUT"
fi

log_test "execute-task.sh accepts --force flag"
OUTPUT=$(bash "$SCRIPT_DIR/execute-task.sh" --help 2>&1 || bash "$SCRIPT_DIR/execute-task.sh" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "\-\-force"; then
  pass
else
  fail "Should document --force flag in usage. Got: $OUTPUT"
fi

# --- Summary ---
echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "Total:  $TEST_COUNT"
green "Passed: $PASS_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  red "Failed: $FAIL_COUNT"
  exit 1
else
  echo "Failed: 0"
  green "All tests passed!"
  exit 0
fi
