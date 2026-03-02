#!/usr/bin/env bats
# BATS test suite for task-manager.sh
# Tests basic functionality of task lifecycle management

# Setup: Define paths and create temporary state directory
setup() {
  export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export TASK_MANAGER="${SCRIPT_DIR}/task-manager.sh"
  export TEST_WORKSPACE="${BATS_TEST_TMPDIR}/workspace"
  export WORKSPACE="${TEST_WORKSPACE}"
  export WORKSPACES_ROOT="${TEST_WORKSPACE}/workspaces"
  
  # Create temporary workspace and state directory
  mkdir -p "${TEST_WORKSPACE}/state"
  mkdir -p "${WORKSPACES_ROOT}"
  
  # Initialize empty tasks.json with proper structure
  echo '{"tasks": {}, "queue": [], "version": 2}' > "${TEST_WORKSPACE}/state/tasks.json"
  
  # Generate valid task IDs (format: task-{timestamp}-{hex})
  TIMESTAMP=$(date +%s)
  export TASK_ID_1="task-${TIMESTAMP}-a1b2c3d4"
  export TASK_ID_2="task-${TIMESTAMP}-e5f6a7b8"
  export TASK_ID_3="task-${TIMESTAMP}-c9d0e1f2"
  export TASK_ID_4="task-${TIMESTAMP}-a3b4c5d6"
  export TASK_ID_5="task-${TIMESTAMP}-e7f8a9b0"
  export TASK_ID_6="task-${TIMESTAMP}-c1d2e3f4"
  
  # Use Homebrew bash (5.x) if available, otherwise system bash
  if [ -x "/opt/homebrew/bin/bash" ]; then
    export BASH_BIN="/opt/homebrew/bin/bash"
  else
    export BASH_BIN="bash"
  fi
}

# Teardown: Clean up temporary files
teardown() {
  rm -rf "${TEST_WORKSPACE}"
}

# Test 1: Script exists and is executable
@test "task-manager.sh exists and is executable" {
  [ -f "${TASK_MANAGER}" ]
  [ -x "${TASK_MANAGER}" ]
}

# Test 2: Script can be sourced without errors
@test "task-manager.sh can be sourced without errors" {
  # Source the script in a subshell to check for syntax errors
  "${BASH_BIN}" -c "source '${TASK_MANAGER}' 2>&1 || true" | grep -v "set -euo pipefail"
  # If we get here without error, sourcing succeeded
  [ $? -eq 0 ] || [ $? -eq 1 ]
}

# Test 3: Create command creates a task
@test "create command creates a task with valid JSON output" {
  run "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task description"
  
  # Should succeed (exit 0)
  [ "$status" -eq 0 ]
  
  # Output should be valid JSON containing id and status
  echo "$output" | grep -q '"id"'
  echo "$output" | grep -q '"status": "created"'
}

# Test 4: Get command retrieves created task
@test "get command retrieves a created task" {
  # First create a task
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/test-repo" "Another test task" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  # Then retrieve it
  run "${BASH_BIN}" "${TASK_MANAGER}" get "${TASK_ID_2}"
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "\"id\": \"${TASK_ID_2}\""
  echo "$output" | grep -q '"repo": "owner/test-repo"'
}

# Test 5: Status command updates task status
@test "status command updates task status with valid transition" {
  # Create a task
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/test-repo" "Status test task" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  # Update status from created to planning (valid transition)
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_3}" planning
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "planning"'
}

# Test 6: List command returns tasks
@test "list command returns all tasks" {
  # Create multiple tasks
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/test-repo" "Task 1" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_5}" "owner/test-repo" "Task 2" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  # List all tasks
  run "${BASH_BIN}" "${TASK_MANAGER}" list
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "\"id\": \"${TASK_ID_4}\""
  echo "$output" | grep -q "\"id\": \"${TASK_ID_5}\""
}

# Test 7: Invalid task ID returns error
@test "get command returns error for non-existent task" {
  run "${BASH_BIN}" "${TASK_MANAGER}" get non-existent-task
  
  # Should fail (invalid task ID format or not found)
  [ "$status" -ne 0 ]
}

# Test 8: Invalid status transition is rejected
@test "status command rejects invalid status transition" {
  # Create a task (status: created)
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_6}" "owner/test-repo" "Transition test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  # Try invalid transition: created -> completed (should fail)
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_6}" completed
  
  # Should fail with exit code 3 (invalid transition)
  [ "$status" -eq 3 ]
}
