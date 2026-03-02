#!/usr/bin/env bash
# substitute.sh — Replace {{var.path}} placeholders in template files
# using values from brain.yaml.
#
# Usage: bash bootstrap/substitute.sh [brain.yaml path]
# Compatible with bash 3.2+ (macOS stock bash)
#
# This script reads brain.yaml, extracts key-value pairs, and performs
# find-and-replace across all template files. It's intentionally simple
# (no YAML parser dependency) — it reads flat key: value lines.

set -euo pipefail

BRAIN_YAML="${1:-brain.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$REPO_ROOT/$BRAIN_YAML" ]]; then
  echo "Error: $BRAIN_YAML not found in $REPO_ROOT"
  exit 1
fi

# ── Parse brain.yaml into parallel arrays (bash 3.2 compatible) ──────────────
# Simple parser: reads "  key: value" lines under "section:" headers.

VAR_KEYS=()
VAR_VALS=()

add_var() {
  VAR_KEYS+=("$1")
  VAR_VALS+=("$2")
}

get_var() {
  local needle="$1"
  local i=0
  while [ $i -lt ${#VAR_KEYS[@]} ]; do
    if [ "${VAR_KEYS[$i]}" = "$needle" ]; then
      echo "${VAR_VALS[$i]}"
      return 0
    fi
    i=$((i + 1))
  done
  echo ""
  return 1
}

current_section=""
while IFS= read -r line; do
  # Skip comments and empty lines
  case "$line" in
    *\#*) line="${line%%#*}" ;;
  esac
  # Check if line is only whitespace
  trimmed="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$trimmed" ] && continue

  # Top-level section (no leading whitespace, ends with colon, no value)
  if echo "$line" | grep -qE '^[a-z_]+:[[:space:]]*$'; then
    current_section="$(echo "$line" | sed 's/:.*//')"
    continue
  fi

  # Key-value pair (indented, under a section)
  if [ -n "$current_section" ] && echo "$line" | grep -qE '^[[:space:]]+[a-z_]+:'; then
    key="$(echo "$line" | sed 's/^[[:space:]]*//;s/:.*//')"
    value="$(echo "$line" | sed 's/^[[:space:]]*[a-z_]*:[[:space:]]*//')"
    # Strip surrounding quotes
    value="$(echo "$value" | sed 's/^"//;s/"$//')"
    # Trim trailing whitespace
    value="$(echo "$value" | sed 's/[[:space:]]*$//')"
    # Skip empty values, booleans, and numbers-only (likely defaults)
    if [ -n "$value" ] && [ "$value" != "false" ] && [ "$value" != "true" ]; then
      add_var "${current_section}.${key}" "$value"
    fi
  fi
done < "$REPO_ROOT/$BRAIN_YAML"

# ── Auto-derive values ───────────────────────────────────────────────────────

agent_id="$(get_var "agent.id" || true)"
agent_branch="$(get_var "agent.branch" || true)"
owner_name="$(get_var "owner.name" || true)"
owner_discord="$(get_var "owner.discord_id" || true)"
owner_telegram="$(get_var "owner.telegram_id" || true)"
security_admin_name="$(get_var "security.admin_name" || true)"
security_admin_id="$(get_var "security.admin_id" || true)"
memory_bank="$(get_var "memory.bank_id" || true)"

if [ -n "$agent_id" ] && [ -z "$agent_branch" ]; then
  add_var "agent.branch" "${agent_id}-live"
fi

if [ -n "$agent_id" ] && [ -z "$memory_bank" ]; then
  add_var "memory.bank_id" "$agent_id"
fi

if [ -z "$security_admin_name" ] && [ -n "$owner_name" ]; then
  add_var "security.admin_name" "$owner_name"
fi

if [ -z "$security_admin_id" ]; then
  if [ -n "$owner_discord" ]; then
    add_var "security.admin_id" "$owner_discord"
  elif [ -n "$owner_telegram" ]; then
    add_var "security.admin_id" "$owner_telegram"
  elif [ -n "$owner_name" ]; then
    add_var "security.admin_id" "$owner_name"
  fi
fi

# Add current date
add_var "date" "$(date +%Y-%m-%d)"

# ── Print parsed variables ───────────────────────────────────────────────────

echo "Parsed variables from $BRAIN_YAML:"
i=0
while [ $i -lt ${#VAR_KEYS[@]} ]; do
  echo "  {{${VAR_KEYS[$i]}}} = ${VAR_VALS[$i]}"
  i=$((i + 1))
done
echo ""

# ── Files to process ─────────────────────────────────────────────────────────

FILES=(
  "AGENTS.md"
  "IDENTITY.md"
  "USER.md"
  "SECURITY.md"
  "RETENTION.md"
  "TOOLS.md"
  "CONTEXT.md"
  "MEMORY.md"
  "LEARNINGS.md"
  "skills/memory-brain/SKILL.md"
  "skills/proactive-agent-behavior/SKILL.md"
)

# ── Perform substitution ─────────────────────────────────────────────────────

substituted=0
for file in "${FILES[@]}"; do
  filepath="$REPO_ROOT/$file"
  if [[ ! -f "$filepath" ]]; then
    echo "  Skip (not found): $file"
    continue
  fi

  changes=0
  i=0
  while [ $i -lt ${#VAR_KEYS[@]} ]; do
    key="${VAR_KEYS[$i]}"
    value="${VAR_VALS[$i]}"
    pattern="{{${key}}}"

    if grep -qF "$pattern" "$filepath" 2>/dev/null; then
      # Escape only & / \ in the replacement value for sed
      escaped_value="$(printf '%s\n' "$value" | sed 's/[&/\]/\\&/g')"
      # Pattern uses | delimiter; {{var.name}} is literal in BRE (no escaping needed)
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|${pattern}|${escaped_value}|g" "$filepath"
      else
        sed -i "s|${pattern}|${escaped_value}|g" "$filepath"
      fi
      changes=$((changes + 1))
    fi
    i=$((i + 1))
  done

  if [[ $changes -gt 0 ]]; then
    echo "  Substituted $changes variable(s) in $file"
    substituted=$((substituted + changes))
  fi
done

echo ""
echo "Done. $substituted total substitution(s) across ${#FILES[@]} files."

# ── Report remaining placeholders ────────────────────────────────────────────

remaining=$(grep -rl '{{[a-z_]*\.[a-z_]*}}' "$REPO_ROOT" \
  --include="*.md" --include="*.json" --include="*.yaml" \
  2>/dev/null \
  | grep -v 'bootstrap/' \
  | grep -v 'plugins/README.md' \
  || true)

if [[ -n "$remaining" ]]; then
  echo ""
  echo "Warning: Files with remaining {{var}} placeholders:"
  echo "$remaining"
  echo "These may need manual filling or indicate missing brain.yaml values."
fi
