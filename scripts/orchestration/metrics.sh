#!/bin/bash
# brain-core orchestration script
# metrics.sh — Performance metrics reporting for coding orchestrator
#
# Computes and displays metrics from tasks.json:
# - Cycle time (created_at → completed_at)
# - Token usage (from token_usage field)
# - Planning accuracy (first-attempt validation pass rate)
#
# Usage:
#   metrics.sh summary       — overall statistics
#   metrics.sh weekly        — this week's statistics
#   metrics.sh task <id>     — single task metrics
#
# Output: Discord-friendly formatted text
#
# Exit codes:
#   0 — Success
#   1 — Invalid arguments
#   2 — Task not found
#   4 — State file I/O error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(pwd)}"
STATE_DIR="${WORKSPACE}/state"
STATE_FILE="${STATE_DIR}/tasks.json"

log() {
  echo "[metrics] $*" >&2
}

ensure_state_file() {
  if [ ! -f "$STATE_FILE" ]; then
    log "ERROR: State file not found: $STATE_FILE"
    exit 4
  fi
}

format_duration() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  
  if [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

cmd_summary() {
  ensure_state_file
  
  python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta

state_file = sys.argv[1]

try:
    with open(state_file, 'r') as f:
        state = json.load(f)
except (json.JSONDecodeError, ValueError) as e:
    print(f'ERROR: Failed to parse state file: {e}', file=sys.stderr)
    sys.exit(4)

tasks = list(state.get('tasks', {}).values())
completed_tasks = [t for t in tasks if t.get('status') == 'completed']

if not completed_tasks:
    print('📊 **Coding Orchestrator Metrics**')
    print('────────────────────────────')
    print('No completed tasks yet.')
    print('────────────────────────────')
    sys.exit(0)

now = datetime.now(timezone.utc)
week_ago = now - timedelta(days=7)

completed_this_week = [
    t for t in completed_tasks
    if t.get('completed_at') and datetime.fromisoformat(t['completed_at'].replace('Z', '+00:00')) >= week_ago
]

total_completed = len(completed_tasks)
completed_week = len(completed_this_week)

cycle_times = [t.get('cycle_time_seconds', 0) for t in completed_tasks if t.get('cycle_time_seconds')]
avg_cycle_time = int(sum(cycle_times) / len(cycle_times)) if cycle_times else 0

first_attempt_passes = [t for t in completed_tasks if t.get('first_attempt_pass') is True]
total_with_validation = [t for t in completed_tasks if t.get('first_attempt_pass') is not None]
pass_rate = int((len(first_attempt_passes) / len(total_with_validation)) * 100) if total_with_validation else 0

total_input_tokens = sum(t.get('token_usage', {}).get('input', 0) for t in completed_tasks)
total_output_tokens = sum(t.get('token_usage', {}).get('output', 0) for t in completed_tasks)
total_tokens = total_input_tokens + total_output_tokens
avg_tokens = int(total_tokens / total_completed) if total_completed else 0

hours = avg_cycle_time // 3600
minutes = (avg_cycle_time % 3600) // 60
avg_time_str = f'{hours}h {minutes}m' if hours > 0 else f'{minutes}m'

print('📊 **Coding Orchestrator Metrics**')
print('────────────────────────────')
print(f'Tasks completed (all time): {total_completed}')
print(f'Tasks completed (this week): {completed_week}')
print(f'Average cycle time: {avg_time_str}')
print(f'First-attempt pass rate: {pass_rate}%')
print(f'Total tokens used: {total_tokens:,}')
print(f'Average tokens per task: {avg_tokens:,}')
print('────────────────────────────')
" "$STATE_FILE"
}

cmd_weekly() {
  ensure_state_file
  
  python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta

state_file = sys.argv[1]

try:
    with open(state_file, 'r') as f:
        state = json.load(f)
except (json.JSONDecodeError, ValueError) as e:
    print(f'ERROR: Failed to parse state file: {e}', file=sys.stderr)
    sys.exit(4)

tasks = list(state.get('tasks', {}).values())
now = datetime.now(timezone.utc)
week_ago = now - timedelta(days=7)

completed_this_week = [
    t for t in tasks
    if t.get('status') == 'completed' and t.get('completed_at') and
       datetime.fromisoformat(t['completed_at'].replace('Z', '+00:00')) >= week_ago
]

if not completed_this_week:
    print('📊 **Weekly Metrics**')
    print('────────────────────────────')
    print('No tasks completed this week.')
    print('────────────────────────────')
    sys.exit(0)

total_completed = len(completed_this_week)

cycle_times = [t.get('cycle_time_seconds', 0) for t in completed_this_week if t.get('cycle_time_seconds')]
avg_cycle_time = int(sum(cycle_times) / len(cycle_times)) if cycle_times else 0

first_attempt_passes = [t for t in completed_this_week if t.get('first_attempt_pass') is True]
total_with_validation = [t for t in completed_this_week if t.get('first_attempt_pass') is not None]
pass_rate = int((len(first_attempt_passes) / len(total_with_validation)) * 100) if total_with_validation else 0

total_input_tokens = sum(t.get('token_usage', {}).get('input', 0) for t in completed_this_week)
total_output_tokens = sum(t.get('token_usage', {}).get('output', 0) for t in completed_this_week)
total_tokens = total_input_tokens + total_output_tokens
avg_tokens = int(total_tokens / total_completed) if total_completed else 0

hours = avg_cycle_time // 3600
minutes = (avg_cycle_time % 3600) // 60
avg_time_str = f'{hours}h {minutes}m' if hours > 0 else f'{minutes}m'

print('📊 **Weekly Metrics**')
print('────────────────────────────')
print(f'Tasks completed: {total_completed}')
print(f'Average cycle time: {avg_time_str}')
print(f'First-attempt pass rate: {pass_rate}%')
print(f'Total tokens used: {total_tokens:,}')
print(f'Average tokens per task: {avg_tokens:,}')
print('────────────────────────────')
" "$STATE_FILE"
}

cmd_task() {
  if [ $# -lt 1 ]; then
    log "Usage: metrics.sh task <task-id>"
    exit 1
  fi
  
  local task_id="$1"
  ensure_state_file
  
  python3 -c "
import json, sys

state_file = sys.argv[1]
task_id = sys.argv[2]

try:
    with open(state_file, 'r') as f:
        state = json.load(f)
except (json.JSONDecodeError, ValueError) as e:
    print(f'ERROR: Failed to parse state file: {e}', file=sys.stderr)
    sys.exit(4)

if task_id not in state.get('tasks', {}):
    print(f'ERROR: Task {task_id} not found', file=sys.stderr)
    sys.exit(2)

task = state['tasks'][task_id]

print(f'📊 **Metrics for {task_id}**')
print('────────────────────────────')
print(f'Status: {task.get(\"status\", \"unknown\")}')
print(f'Description: {task.get(\"description\", \"N/A\")[:60]}')

if task.get('cycle_time_seconds') is not None:
    seconds = task['cycle_time_seconds']
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    time_str = f'{hours}h {minutes}m' if hours > 0 else f'{minutes}m'
    print(f'Cycle time: {time_str}')
else:
    print('Cycle time: N/A (not completed)')

validation_attempts = task.get('validation_attempts', 0)
print(f'Validation attempts: {validation_attempts}')

first_pass = task.get('first_attempt_pass')
if first_pass is True:
    print('First-attempt pass: ✅ Yes')
elif first_pass is False:
    print('First-attempt pass: ❌ No')
else:
    print('First-attempt pass: N/A')

token_usage = task.get('token_usage', {})
input_tokens = token_usage.get('input', 0)
output_tokens = token_usage.get('output', 0)
total_tokens = input_tokens + output_tokens
cost = token_usage.get('cost_usd', 0.0)

print(f'Tokens: {total_tokens:,} (in: {input_tokens:,}, out: {output_tokens:,})')
if cost > 0:
    print(f'Cost: \${cost:.4f}')

print('────────────────────────────')
" "$STATE_FILE" "$task_id"
}

if [ $# -lt 1 ]; then
  log "Usage: metrics.sh <command> [args...]"
  log "Commands: summary, weekly, task <id>"
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  summary) cmd_summary "$@" ;;
  weekly)  cmd_weekly "$@" ;;
  task)    cmd_task "$@" ;;
  *)
    log "ERROR: Unknown command '$COMMAND'. Valid: summary, weekly, task"
    exit 1
    ;;
esac
