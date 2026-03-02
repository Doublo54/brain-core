#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# validate-task.sh — Validation gate: lint/typecheck/test/build with retry
#
# Runs validation steps against a task workspace before code review.
# Reads package.json to discover available scripts, then executes them
# in sequence: lint → typecheck → test → build. Missing scripts are skipped.
#
# Designed to slot into the task-manager.sh state machine as a formal step
# between "executing" and "code_review" (the VALIDATING state).
#
# Integration with task-manager.sh:
#   1. After execute-task.sh completes, transition task to "validating":
#        task-manager.sh status <task-id> validating
#   2. Run this script:
#        validate-task.sh <workspace-path>
#   3. On success (exit 0): transition to "code_review":
#        task-manager.sh status <task-id> code_review
#   4. On failure (exit 1): transition back to "executing" for retry or to "failed":
#        task-manager.sh status <task-id> executing   # retry
#        task-manager.sh status <task-id> failed       # give up
#
# Usage:
#   validate-task.sh <workspace-path>
#
# Output (stdout): JSON result object
#   { "status": "pass"|"fail", "attempts": N, "steps": [...], "errors": "..." }
#
# Logging (stderr): progress/errors
#
# Exit codes:
#   0 — All validation steps passed
#   1 — Validation failed after max retries, or invalid arguments
#   2 — Workspace not found or missing package.json

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ATTEMPTS=3

# Validation steps in execution order.
# Each entry is "step_name:script_variant1,script_variant2,..."
# First matching variant found in package.json scripts is used.
VALIDATION_STEPS=(
  "lint:lint"
  "typecheck:typecheck,type-check,check,tsc"
  "test:test"
  "build:build"
)

# --- Logging (all to stderr, matching task-manager.sh style) ---
log() {
  echo "[validate-task] $*" >&2
}

# --- Discover available npm scripts from package.json ---
# Uses python3 (no jq dependency). Outputs JSON: {"lint":"lint","typecheck":"tsc",...}
# Only includes steps that have a matching script in package.json.
discover_scripts() {
  local workspace_path="$1"
  local pkg_json="${workspace_path}/package.json"

  if [[ ! -f "$pkg_json" ]]; then
    log "ERROR: No package.json found at ${pkg_json}"
    return 2
  fi

  python3 -c "
import json, sys

pkg_path = sys.argv[1]
steps_raw = sys.argv[2:]

try:
    with open(pkg_path, 'r') as f:
        pkg = json.load(f)
except (json.JSONDecodeError, ValueError, FileNotFoundError) as e:
    print(json.dumps({'error': str(e)}), file=sys.stderr)
    sys.exit(2)

scripts = pkg.get('scripts', {})
discovered = {}

for step_def in steps_raw:
    parts = step_def.split(':', 1)
    step_name = parts[0]
    variants = parts[1].split(',') if len(parts) > 1 else [step_name]

    for variant in variants:
        if variant in scripts:
            discovered[step_name] = variant
            break

print(json.dumps(discovered))
" "$pkg_json" "${VALIDATION_STEPS[@]}"
}

# --- Run a single validation step ---
# Returns 0 on success, 1 on failure.
# Captures stdout+stderr into the provided output variable name.
run_step() {
  local workspace_path="$1"
  local script_name="$2"
  local step_output_file="$3"

  local start_ms
  start_ms=$(python3 -c "import time; print(int(time.time()*1000))")

  local exit_code=0
  npm run "$script_name" --prefix "$workspace_path" > "$step_output_file" 2>&1 || exit_code=$?

  local end_ms
  end_ms=$(python3 -c "import time; print(int(time.time()*1000))")
  local duration_ms=$(( end_ms - start_ms ))

  # ___STEP_META___ sentinel: encodes exit_code:duration for caller extraction
  echo "___STEP_META___:${exit_code}:${duration_ms}" >> "$step_output_file"

  return "$exit_code"
}

# --- Run all validation steps for one attempt ---
# Returns 0 if all steps pass, 1 if any step fails.
# Writes step results JSON array to the provided file.
run_all_steps() {
  local workspace_path="$1"
  local discovered_json="$2"
  local steps_result_file="$3"
  local errors_file="$4"

  local all_passed=true

  echo "[" > "$steps_result_file"
  local first_step=true

  for step_def in "${VALIDATION_STEPS[@]}"; do
    local step_name="${step_def%%:*}"

    local script_name
    script_name=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get(sys.argv[2], ''))
" "$discovered_json" "$step_name")

    if [[ "$first_step" == "true" ]]; then
      first_step=false
    else
      echo "," >> "$steps_result_file"
    fi

    if [[ -z "$script_name" ]]; then
      log "  ⏭  ${step_name}: skipped (no script found)"
      printf '  {"name": "%s", "script": null, "status": "skipped", "duration_ms": 0}' \
        "$step_name" >> "$steps_result_file"
      continue
    fi

    log "  ▶  ${step_name}: running 'npm run ${script_name}'..."

    local step_output_file
    step_output_file=$(mktemp)

    if run_step "$workspace_path" "$script_name" "$step_output_file"; then
      local meta_line
      meta_line=$(grep "___STEP_META___" "$step_output_file" | tail -1)
      local duration_ms
      duration_ms=$(echo "$meta_line" | cut -d: -f3)

      log "  ✓  ${step_name}: passed (${duration_ms}ms)"
      printf '  {"name": "%s", "script": "%s", "status": "pass", "duration_ms": %s}' \
        "$step_name" "$script_name" "${duration_ms:-0}" >> "$steps_result_file"
    else
      local meta_line
      meta_line=$(grep "___STEP_META___" "$step_output_file" | tail -1)
      local duration_ms
      duration_ms=$(echo "$meta_line" | cut -d: -f3)

      grep -v "___STEP_META___" "$step_output_file" >> "$errors_file" 2>/dev/null || true

      log "  ✗  ${step_name}: FAILED (${duration_ms}ms)"
      printf '  {"name": "%s", "script": "%s", "status": "fail", "duration_ms": %s}' \
        "$step_name" "$script_name" "${duration_ms:-0}" >> "$steps_result_file"
      all_passed=false
    fi

    rm -f "$step_output_file"

    if [[ "$all_passed" == "false" ]]; then
      # Append remaining steps as skipped, then break for retry
      for remaining_def in "${VALIDATION_STEPS[@]}"; do
        local remaining_name="${remaining_def%%:*}"
        if [[ "$remaining_name" == "$step_name" ]]; then
          continue
        fi
        local found_failed=false
        for check_def in "${VALIDATION_STEPS[@]}"; do
          local check_name="${check_def%%:*}"
          if [[ "$check_name" == "$step_name" ]]; then
            found_failed=true
            continue
          fi
          if [[ "$found_failed" == "true" && "$check_name" == "$remaining_name" ]]; then
            echo "," >> "$steps_result_file"
            printf '  {"name": "%s", "script": null, "status": "skipped", "duration_ms": 0}' \
              "$remaining_name" >> "$steps_result_file"
          fi
        done
      done
      break
    fi
  done

  echo "" >> "$steps_result_file"
  echo "]" >> "$steps_result_file"

  if [[ "$all_passed" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  log "Usage: validate-task.sh <workspace-path>"
  exit 1
fi

TASK_WORKSPACE="$1"

if [[ ! -d "$TASK_WORKSPACE" ]]; then
  log "ERROR: Workspace directory not found: ${TASK_WORKSPACE}"
  echo '{"status": "fail", "attempts": 0, "steps": [], "errors": "Workspace directory not found"}'
  exit 2
fi

if [[ ! -f "${TASK_WORKSPACE}/package.json" ]]; then
  log "ERROR: No package.json in workspace: ${TASK_WORKSPACE}"
  echo '{"status": "fail", "attempts": 0, "steps": [], "errors": "No package.json found in workspace"}'
  exit 2
fi

log "Discovering validation scripts in ${TASK_WORKSPACE}/package.json..."
DISCOVERED_JSON=$(discover_scripts "$TASK_WORKSPACE") || {
  log "ERROR: Failed to read package.json"
  echo '{"status": "fail", "attempts": 0, "steps": [], "errors": "Failed to read package.json"}'
  exit 2
}

SCRIPT_COUNT=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$DISCOVERED_JSON")
if [[ "$SCRIPT_COUNT" -eq 0 ]]; then
  log "No validation scripts found in package.json — passing vacuously"
  echo '{"status": "pass", "attempts": 0, "steps": [], "errors": ""}'
  exit 0
fi

log "Found ${SCRIPT_COUNT} validation script(s)"

ATTEMPT=0
LAST_STEPS_FILE=""
LAST_ERRORS=""

# Retries handle transient failures (npm cache, network, flaky tests).
# Deterministic failures (lint, type errors) will fail identically each attempt —
# that's expected. The orchestrator handles code-level fixes by transitioning
# back to "executing" (see header comments).
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  log "--- Validation attempt ${ATTEMPT}/${MAX_ATTEMPTS} ---"

  STEPS_FILE=$(mktemp)
  ERRORS_FILE=$(mktemp)

  if run_all_steps "$TASK_WORKSPACE" "$DISCOVERED_JSON" "$STEPS_FILE" "$ERRORS_FILE"; then
    log "Validation PASSED on attempt ${ATTEMPT}"

    STEPS_JSON=$(cat "$STEPS_FILE")
    rm -f "$STEPS_FILE" "$ERRORS_FILE"

    python3 -c "
import json, sys

steps = json.loads(sys.argv[1])
result = {
    'status': 'pass',
    'attempts': int(sys.argv[2]),
    'steps': steps,
    'errors': ''
}
print(json.dumps(result, indent=2))
" "$STEPS_JSON" "$ATTEMPT"

    exit 0
  fi

  LAST_STEPS_FILE="$STEPS_FILE"
  LAST_ERRORS=$(cat "$ERRORS_FILE" 2>/dev/null || echo "")
  rm -f "$ERRORS_FILE"

  if [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; then
    log "Retrying... (${ATTEMPT}/${MAX_ATTEMPTS} attempts used)"
  fi
done

log "Validation FAILED after ${MAX_ATTEMPTS} attempts"

STEPS_JSON=$(cat "$LAST_STEPS_FILE" 2>/dev/null || echo "[]")
rm -f "$LAST_STEPS_FILE"

TRUNCATED_ERRORS=$(python3 -c "
import sys
errors = sys.argv[1] if len(sys.argv) > 1 else ''
# Escape for JSON embedding
errors = errors.replace('\\\\', '\\\\\\\\').replace('\"', '\\\\\"').replace('\n', '\\\\n').replace('\r', '\\\\r').replace('\t', '\\\\t')
if len(errors) > 4000:
    errors = errors[:3990] + '...[truncated]'
print(errors)
" "$LAST_ERRORS")

python3 -c "
import json, sys

steps_raw = sys.argv[1]
attempts = int(sys.argv[2])
errors = sys.argv[3] if len(sys.argv) > 3 else ''

try:
    steps = json.loads(steps_raw)
except (json.JSONDecodeError, ValueError):
    steps = []

result = {
    'status': 'fail',
    'attempts': attempts,
    'steps': steps,
    'errors': errors
}
print(json.dumps(result, indent=2))
" "$STEPS_JSON" "$MAX_ATTEMPTS" "$TRUNCATED_ERRORS"

exit 1
