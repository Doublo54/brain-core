#!/usr/bin/env bats

setup() {
  export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export TASK_MANAGER="${SCRIPT_DIR}/task-manager.sh"
  export METRICS="${SCRIPT_DIR}/metrics.sh"
  export TEST_WORKSPACE="${BATS_TEST_TMPDIR}/workspace"
  export WORKSPACE="${TEST_WORKSPACE}"
  export WORKSPACES_ROOT="${TEST_WORKSPACE}/workspaces"
  
  mkdir -p "${TEST_WORKSPACE}/state"
  mkdir -p "${WORKSPACES_ROOT}"
  
  echo '{"tasks": {}, "queue": [], "version": 2}' > "${TEST_WORKSPACE}/state/tasks.json"
  
  TIMESTAMP=$(date +%s)
  export TASK_ID_1="task-${TIMESTAMP}-a1b2c3d4"
  export TASK_ID_2="task-${TIMESTAMP}-e5f6a7b8"
  
  if [ -x "/opt/homebrew/bin/bash" ]; then
    export BASH_BIN="/opt/homebrew/bin/bash"
  else
    export BASH_BIN="bash"
  fi
}

teardown() {
  rm -rf "${TEST_WORKSPACE}"
}

@test "metrics.sh exists and is executable" {
  [ -f "${METRICS}" ]
  [ -x "${METRICS}" ]
}

@test "cycle_time_seconds computed on task completion" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task" 2>/dev/null > /dev/null
  
  sleep 2
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" plan_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" approved 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" code_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" qa 2>/dev/null > /dev/null
  
  result=$("${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" completed 2>/dev/null)
  
  echo "$result" | grep -q '"cycle_time_seconds"'
  echo "$result" | grep -q '"completed_at"'
  
  cycle_time=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cycle_time_seconds', 0))")
  [ "$cycle_time" -ge 2 ]
}

@test "validation_attempts incremented on validating transition" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task" 2>/dev/null > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" plan_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" approved 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  
  result=$("${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null)
  
  attempts=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('validation_attempts', 0))")
  [ "$attempts" -eq 1 ]
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  
  result=$("${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null)
  
  attempts=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('validation_attempts', 0))")
  [ "$attempts" -eq 2 ]
}

@test "first_attempt_pass set to true when validation passes on first try" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task" 2>/dev/null > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" plan_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" approved 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null > /dev/null
  
  result=$("${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" code_review 2>/dev/null)
  
  first_pass=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('first_attempt_pass', 'null'))")
  [ "$first_pass" = "True" ]
}

@test "first_attempt_pass set to false when validation fails on first try" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task" 2>/dev/null > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" plan_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" approved 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null > /dev/null
  
  result=$("${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" code_review 2>/dev/null)
  
  first_pass=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('first_attempt_pass', 'null'))")
  [ "$first_pass" = "False" ]
}

@test "set-tokens command updates token usage" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" set-tokens "${TASK_ID_1}" 1000 500 0.05
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"input": 1000'
  echo "$output" | grep -q '"output": 500'
  echo "$output" | grep -q '"cost_usd": 0.05'
}

@test "metrics.sh summary produces output with empty tasks" {
  run "${BASH_BIN}" "${METRICS}" summary
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Coding Orchestrator Metrics"
  echo "$output" | grep -q "No completed tasks yet"
}

@test "metrics.sh summary produces output with completed tasks" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task 1" 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/test-repo" "Test task 2" 2>/dev/null > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" plan_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" approved 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" executing 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" validating 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" code_review 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" qa 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" completed 2>/dev/null > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" set-tokens "${TASK_ID_1}" 5000 2500 0.15 2>/dev/null > /dev/null
  
  run "${BASH_BIN}" "${METRICS}" summary
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Tasks completed (all time): 1"
  echo "$output" | grep -q "Average cycle time:"
  echo "$output" | grep -q "First-attempt pass rate:"
  echo "$output" | grep -q "Total tokens used:"
}

@test "metrics.sh task displays single task metrics" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/test-repo" "Test task" 2>/dev/null > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" set-tokens "${TASK_ID_1}" 3000 1500 0.08 2>/dev/null > /dev/null
  
  run "${BASH_BIN}" "${METRICS}" task "${TASK_ID_1}"
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Metrics for ${TASK_ID_1}"
  echo "$output" | grep -q "Status: created"
  echo "$output" | grep -q "Tokens: 4,500"
}

@test "metrics.sh weekly handles empty week" {
  run "${BASH_BIN}" "${METRICS}" weekly
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Weekly Metrics"
  echo "$output" | grep -q "No tasks completed this week"
}
