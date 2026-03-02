#!/usr/bin/env bash
set -euo pipefail

# CI validation: sandbox modes must match tier declarations across all agents.
# Checks:
#   1. sandbox.mode matches tier (admin/trusted → off, standard → all)
#
# Usage:
#   validate-permissions.sh [--config <path>] [--brain-dir <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"

CONFIG_PATH="${REPO_ROOT}/defizoo-brain/config/openclaw.json.template"
BRAIN_DIR="${REPO_ROOT}/defizoo-brain/agents"

while [[ $# -gt 0 ]]; do
  case $1 in
    --config)    CONFIG_PATH="$2"; shift 2 ;;
    --brain-dir) BRAIN_DIR="$2"; shift 2 ;;
    *)           echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "ERROR: Config not found: $CONFIG_PATH" >&2
  exit 1
fi

if [[ ! -d "$BRAIN_DIR" ]]; then
  echo "ERROR: Brain directory not found: $BRAIN_DIR" >&2
  exit 1
fi

ERRORS=0
CHECKED=0

echo "Validating sandbox configuration..."

AGENT_DATA=$(CONFIG_PATH="$CONFIG_PATH" python3 -c '
import json, re, os

config_path = os.environ["CONFIG_PATH"]
c = open(config_path).read()
c = re.sub(r"\"\$\{[^}]+\}\"", "\"PH\"", c)
c = re.sub(r"\$\{[^}]+\}", "PH", c)
config = json.loads(c)

for agent in config["agents"]["list"]:
    aid = agent["id"]
    smode = agent.get("sandbox", {}).get("mode", "unknown")
    print(f"{aid}|{smode}")
')

declare -A TIER_SANDBOX=(
  [admin]="off"
  [trusted]="off"
  [standard]="all"
)

while IFS='|' read -r agent_id sandbox_mode; do
  CHECKED=$((CHECKED + 1))

  brain_yaml="${BRAIN_DIR}/${agent_id}/brain.yaml"
  if [[ ! -f "$brain_yaml" ]]; then
    echo "[FAIL] ${agent_id}: brain.yaml not found at ${brain_yaml}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  tier=$(python3 -c "
import sys
for line in open(sys.argv[1]):
    l = line.strip()
    if l.startswith('tier:'):
        print(l.split(':', 1)[1].strip().strip('\"').strip(\"'\"))
        break
" "$brain_yaml")

  if [[ -z "$tier" ]]; then
    echo "[FAIL] ${agent_id}: no tier found in brain.yaml"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  expected_sandbox="${TIER_SANDBOX[$tier]:-}"
  if [[ -z "$expected_sandbox" ]]; then
    echo "[FAIL] ${agent_id}: unknown tier '${tier}'"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  if [[ "$sandbox_mode" != "$expected_sandbox" ]]; then
    echo "[FAIL] ${agent_id}: ${tier} tier expects sandbox=${expected_sandbox}, got sandbox=${sandbox_mode}"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  echo "[OK] ${agent_id}: ${tier} tier, sandbox=${sandbox_mode}"
done <<< "$AGENT_DATA"

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "${CHECKED} agents checked: ${ERRORS} FAILED"
  exit 1
else
  echo "All ${CHECKED} agents: sandbox configuration VALID"
  exit 0
fi
