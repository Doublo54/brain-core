#!/usr/bin/env bats

setup() {
  export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export TASK_MANAGER="${SCRIPT_DIR}/task-manager.sh"
  export TEST_WORKSPACE="${BATS_TEST_TMPDIR}/workspace"
  export WORKSPACE="${TEST_WORKSPACE}"
  export WORKSPACES_ROOT="${TEST_WORKSPACE}/workspaces"
  
  mkdir -p "${TEST_WORKSPACE}/state"
  mkdir -p "${WORKSPACES_ROOT}"
  
  echo '{"tasks": {}, "queue": [], "version": 2}' > "${TEST_WORKSPACE}/state/tasks.json"
  
  TIMESTAMP=$(date +%s)
  export TASK_ID_QA="task-${TIMESTAMP}-abcd1234"
  
  if [ -x "/opt/homebrew/bin/bash" ]; then
    export BASH_BIN="/opt/homebrew/bin/bash"
  else
    export BASH_BIN="bash"
  fi
}

teardown() {
  rm -rf "${TEST_WORKSPACE}"
}

@test "task can transition from code_review to qa" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA test task" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "qa"'
}

@test "qa_entered_at timestamp is set when entering qa state" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA timestamp test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"qa_entered_at"'
}

@test "task can transition from qa to completed (approval)" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA approval test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null

  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" completed

  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "completed"'
}

@test "qa_approved_at timestamp is set when transitioning from qa to completed" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA approval timestamp test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null

  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" completed
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"qa_approved_at"'
}

@test "task can transition from qa to executing (rejection)" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA rejection test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "executing"'
}

@test "qa_rejection_count is incremented when transitioning from qa to executing" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA rejection count test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"qa_rejection_count": 1'
}

@test "invalid transition from qa to created is rejected" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "Invalid transition test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" created
  
  [ "$status" -eq 3 ]
}

@test "invalid transition from qa to code_review is rejected" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "Invalid transition test 2" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null

  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review

  [ "$status" -eq 3 ]
}

@test "task can transition from qa to blocked" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "QA blocked test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" blocked
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "blocked"'
}

@test "task can transition from blocked to qa" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_QA}" "owner/test-repo" "Blocked to QA test" 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" planning 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" plan_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" approved 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" executing 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" validating 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" code_review 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" blocked 2>&1 | grep -v "^\[task-mgr\]" > /dev/null
  
  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_QA}" qa
  
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "qa"'
}
