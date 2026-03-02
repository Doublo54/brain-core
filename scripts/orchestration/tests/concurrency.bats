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
  export TASK_ID_1="task-${TIMESTAMP}-a1b2c3d4"
  export TASK_ID_2="task-${TIMESTAMP}-e5f6a7b8"
  export TASK_ID_3="task-${TIMESTAMP}-c9d0e1f2"
  export TASK_ID_4="task-${TIMESTAMP}-a3b4c5d6"
  export TASK_ID_5="task-${TIMESTAMP}-e7f8a9b0"

  if [ -x "/opt/homebrew/bin/bash" ]; then
    export BASH_BIN="/opt/homebrew/bin/bash"
  else
    export BASH_BIN="bash"
  fi

  export MAX_CONCURRENT_TASKS=3
}

teardown() {
  rm -rf "${TEST_WORKSPACE}"
}

@test "creating up to MAX_CONCURRENT_TASKS tasks gives 'created' state" {
  for id in "$TASK_ID_1" "$TASK_ID_2" "$TASK_ID_3"; do
    run "${BASH_BIN}" "${TASK_MANAGER}" create "$id" "owner/repo" "Test task"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"status": "created"'
  done
}

@test "creating MAX_CONCURRENT_TASKS+1 task gives 'queued' state" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/repo" "Task 3" > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/repo" "Task 4 (should queue)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "queued"'
}

@test "dequeue promotes queued task to 'created' when slot opens" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/repo" "Task 3" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/repo" "Task 4 queued" > /dev/null 2>&1

  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning --force > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" failed --force > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" dequeue
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "\"promoted\""
  echo "$output" | grep -q "${TASK_ID_4}"

  run "${BASH_BIN}" "${TASK_MANAGER}" get "${TASK_ID_4}"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "created"'
}

@test "dequeue with no available slots promotes nothing" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/repo" "Task 3" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/repo" "Task 4 queued" > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" dequeue
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"promoted": \[\]'

  run "${BASH_BIN}" "${TASK_MANAGER}" get "${TASK_ID_4}"
  echo "$output" | grep -q '"status": "queued"'
}

@test "queue-status shows correct counts" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/repo" "Task 3" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/repo" "Task 4 queued" > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" queue-status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"active": 3'
  echo "$output" | grep -q '"queued": 1'
  echo "$output" | grep -q '"max_concurrent": 3'
  echo "$output" | grep -q '"available_slots": 0'
}

@test "queue-status shows available slots when under capacity" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" queue-status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"active": 1'
  echo "$output" | grep -q '"queued": 0'
  echo "$output" | grep -q '"available_slots": 2'
}

@test "multiple queued tasks dequeue in FIFO order" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/repo" "Task 3" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/repo" "Queued 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_5}" "owner/repo" "Queued 2" > /dev/null 2>&1

  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" planning --force > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_1}" failed --force > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" dequeue
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "${TASK_ID_4}"

  run "${BASH_BIN}" "${TASK_MANAGER}" get "${TASK_ID_4}"
  echo "$output" | grep -q '"status": "created"'

  run "${BASH_BIN}" "${TASK_MANAGER}" get "${TASK_ID_5}"
  echo "$output" | grep -q '"status": "queued"'
}

@test "queued task can be aborted" {
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_3}" "owner/repo" "Task 3" > /dev/null 2>&1
  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_4}" "owner/repo" "Queued" > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" status "${TASK_ID_4}" aborted
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "aborted"'
}

@test "custom MAX_CONCURRENT_TASKS is respected" {
  export MAX_CONCURRENT_TASKS=1

  "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_1}" "owner/repo" "Task 1" > /dev/null 2>&1

  run "${BASH_BIN}" "${TASK_MANAGER}" create "${TASK_ID_2}" "owner/repo" "Task 2 should queue"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status": "queued"'
}
