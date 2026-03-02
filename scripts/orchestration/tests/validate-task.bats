#!/usr/bin/env bats

setup() {
  export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export VALIDATE_TASK="${SCRIPT_DIR}/validate-task.sh"
  export TEST_WORKSPACE="${BATS_TEST_TMPDIR}/workspace"

  mkdir -p "${TEST_WORKSPACE}"

  if [ -x "/opt/homebrew/bin/bash" ]; then
    export BASH_BIN="/opt/homebrew/bin/bash"
  else
    export BASH_BIN="bash"
  fi
}

teardown() {
  rm -rf "${TEST_WORKSPACE}"
}

create_package_json() {
  local workspace="$1"
  local scripts_json="$2"
  cat > "${workspace}/package.json" <<EOF
{
  "name": "test-project",
  "version": "1.0.0",
  "scripts": ${scripts_json}
}
EOF
}

create_passing_npm_script() {
  local workspace="$1"
  local script_name="$2"
  mkdir -p "${workspace}/node_modules/.bin"
  mkdir -p "${workspace}/scripts"
  cat > "${workspace}/scripts/${script_name}.sh" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
  chmod +x "${workspace}/scripts/${script_name}.sh"
}

create_failing_npm_script() {
  local workspace="$1"
  local script_name="$2"
  local error_msg="${3:-${script_name} failed}"
  mkdir -p "${workspace}/node_modules/.bin"
  mkdir -p "${workspace}/scripts"
  cat > "${workspace}/scripts/${script_name}.sh" <<SCRIPT
#!/bin/bash
echo "${error_msg}" >&2
exit 1
SCRIPT
  chmod +x "${workspace}/scripts/${script_name}.sh"
}

bats_require_minimum_version 1.5.0

@test "validate-task.sh exists and is executable" {
  [ -f "${VALIDATE_TASK}" ]
  [ -x "${VALIDATE_TASK}" ]
}

@test "exits 1 with no arguments" {
  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}"
  [ "$status" -eq 1 ]
}

@test "exits 2 for non-existent workspace directory" {
  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "/nonexistent/path/xyz"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='fail'"
}

@test "exits 2 when workspace has no package.json" {
  mkdir -p "${TEST_WORKSPACE}/empty-ws"
  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "${TEST_WORKSPACE}/empty-ws"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='fail'"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'package.json' in d['errors']"
}

@test "passes vacuously when package.json has no validation scripts" {
  local ws="${TEST_WORKSPACE}/no-scripts"
  mkdir -p "$ws"
  create_package_json "$ws" '{"start": "node index.js", "dev": "nodemon"}'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='pass'"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['attempts']==0"
}

@test "passes when all validation scripts succeed" {
  local ws="${TEST_WORKSPACE}/all-pass"
  mkdir -p "$ws"

  create_passing_npm_script "$ws" "lint"
  create_passing_npm_script "$ws" "typecheck"
  create_passing_npm_script "$ws" "test"
  create_passing_npm_script "$ws" "build"

  create_package_json "$ws" '{
    "lint": "bash scripts/lint.sh",
    "typecheck": "bash scripts/typecheck.sh",
    "test": "bash scripts/test.sh",
    "build": "bash scripts/build.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'pass', f'Expected pass, got {d[\"status\"]}'
assert d['attempts'] == 1
assert len(d['steps']) == 4
for step in d['steps']:
    assert step['status'] == 'pass', f'Step {step[\"name\"]} expected pass, got {step[\"status\"]}'
"
}

@test "skips missing scripts and passes with partial set" {
  local ws="${TEST_WORKSPACE}/partial"
  mkdir -p "$ws"

  create_passing_npm_script "$ws" "lint"
  create_passing_npm_script "$ws" "build"

  create_package_json "$ws" '{
    "lint": "bash scripts/lint.sh",
    "build": "bash scripts/build.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'pass'
steps_by_name = {s['name']: s for s in d['steps']}
assert steps_by_name['lint']['status'] == 'pass'
assert steps_by_name['typecheck']['status'] == 'skipped'
assert steps_by_name['test']['status'] == 'skipped'
assert steps_by_name['build']['status'] == 'pass'
"
}

@test "retries 3 times on lint failure then reports fail" {
  local ws="${TEST_WORKSPACE}/fail-lint"
  mkdir -p "$ws"

  create_failing_npm_script "$ws" "lint" "eslint: 5 errors found"

  create_package_json "$ws" '{
    "lint": "bash scripts/lint.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'fail', f'Expected fail, got {d[\"status\"]}'
assert d['attempts'] == 3, f'Expected 3 attempts, got {d[\"attempts\"]}'
"
}

@test "logs show all 3 retry attempts" {
  local ws="${TEST_WORKSPACE}/retry-logs"
  mkdir -p "$ws"

  create_failing_npm_script "$ws" "lint" "lint error"

  create_package_json "$ws" '{
    "lint": "bash scripts/lint.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 1 ]

  local attempt_1_count
  attempt_1_count=$(echo "$stderr" | grep -c "attempt 1/3" || true)
  local attempt_2_count
  attempt_2_count=$(echo "$stderr" | grep -c "attempt 2/3" || true)
  local attempt_3_count
  attempt_3_count=$(echo "$stderr" | grep -c "attempt 3/3" || true)

  [ "$attempt_1_count" -ge 1 ]
  [ "$attempt_2_count" -ge 1 ]
  [ "$attempt_3_count" -ge 1 ]
}

@test "discovers type-check variant for typecheck step" {
  local ws="${TEST_WORKSPACE}/typecheck-variant"
  mkdir -p "$ws"

  create_passing_npm_script "$ws" "type-check"

  create_package_json "$ws" '{
    "type-check": "bash scripts/type-check.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'pass'
steps_by_name = {s['name']: s for s in d['steps']}
assert steps_by_name['typecheck']['status'] == 'pass'
assert steps_by_name['typecheck']['script'] == 'type-check'
"
}

@test "discovers tsc variant for typecheck step" {
  local ws="${TEST_WORKSPACE}/tsc-variant"
  mkdir -p "$ws"

  create_passing_npm_script "$ws" "tsc"

  create_package_json "$ws" '{
    "tsc": "bash scripts/tsc.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
steps_by_name = {s['name']: s for s in d['steps']}
assert steps_by_name['typecheck']['script'] == 'tsc'
"
}

@test "stops at first failing step and marks rest as skipped" {
  local ws="${TEST_WORKSPACE}/stop-early"
  mkdir -p "$ws"

  create_passing_npm_script "$ws" "lint"
  create_failing_npm_script "$ws" "typecheck" "type error"
  create_passing_npm_script "$ws" "test"
  create_passing_npm_script "$ws" "build"

  create_package_json "$ws" '{
    "lint": "bash scripts/lint.sh",
    "typecheck": "bash scripts/typecheck.sh",
    "test": "bash scripts/test.sh",
    "build": "bash scripts/build.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'fail'
steps_by_name = {s['name']: s for s in d['steps']}
assert steps_by_name['lint']['status'] == 'pass'
assert steps_by_name['typecheck']['status'] == 'fail'
assert steps_by_name['test']['status'] == 'skipped'
assert steps_by_name['build']['status'] == 'skipped'
"
}

@test "outputs valid JSON on success" {
  local ws="${TEST_WORKSPACE}/json-valid"
  mkdir -p "$ws"

  create_passing_npm_script "$ws" "build"

  create_package_json "$ws" '{
    "build": "bash scripts/build.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'status' in d
assert 'attempts' in d
assert 'steps' in d
assert 'errors' in d
assert isinstance(d['steps'], list)
"
}

@test "outputs valid JSON on failure" {
  local ws="${TEST_WORKSPACE}/json-fail"
  mkdir -p "$ws"

  create_failing_npm_script "$ws" "build" "compilation failed"

  create_package_json "$ws" '{
    "build": "bash scripts/build.sh"
  }'

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'fail'
assert 'attempts' in d
assert 'steps' in d
assert 'errors' in d
"
}

@test "exits 2 for malformed package.json" {
  local ws="${TEST_WORKSPACE}/malformed"
  mkdir -p "$ws"
  echo "not valid json {{{" > "${ws}/package.json"

  run --separate-stderr "${BASH_BIN}" "${VALIDATE_TASK}" "$ws"
  [ "$status" -eq 2 ]
}
