#!/usr/bin/env bash
# migrate-brain-yaml.sh — Migrate flat brain.yaml to nested schema
#
# Usage: bash migrate-brain-yaml.sh <input-flat-brain.yaml> <output-nested-brain.yaml>
#
# Converts flat schema (agent_id, name, deploy_mode, etc.) to nested schema
# matching brain-core/template/brain.yaml structure.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <input-flat-brain.yaml> <output-nested-brain.yaml>"
  exit 1
fi

INPUT="$1"
OUTPUT="$2"

if [[ ! -f "$INPUT" ]]; then
  echo "Error: Input file not found: $INPUT"
  exit 1
fi

# ── Parse flat schema ─────────────────────────────────────────────────────────

agent_id=""
name=""
description=""
deploy_mode=""
memory_backend=""
skills=()

# Extract header comments (first block before any YAML keys)
header_comments=""
in_header=true

while IFS= read -r line; do
  # If we hit a non-comment, non-empty line, we're past the header
  if [[ "$line" =~ ^[a-z_]+: ]] || [[ "$line" =~ ^skills: ]]; then
    in_header=false
  fi
  
  if $in_header; then
    if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
      header_comments+="$line"$'\n'
    fi
  fi
  
  # Parse flat keys
  if [[ "$line" =~ ^agent_id:[[:space:]]*(.*) ]]; then
    agent_id="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^name:[[:space:]]*(.*) ]]; then
    name="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^description:[[:space:]]*(.*) ]]; then
    description="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^deploy_mode:[[:space:]]*(.*) ]]; then
    deploy_mode="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^memory_backend:[[:space:]]*(.*) ]]; then
    memory_backend="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^[[:space:]]+-[[:space:]]*(.*) ]]; then
    # Skill list item
    skills+=("${BASH_REMATCH[1]}")
  fi
done < "$INPUT"

# ── Map values ────────────────────────────────────────────────────────────────

# Map deploy_mode: main → deployment.mode: standalone
deployment_mode="standalone"
if [[ "$deploy_mode" == "main" ]]; then
  deployment_mode="standalone"
fi

# Map memory_backend: sqlite → memory.backend: builtin
memory_backend_mapped="builtin"
if [[ "$memory_backend" == "sqlite" ]]; then
  memory_backend_mapped="builtin"
fi

# ── Generate nested schema ────────────────────────────────────────────────────

cat > "$OUTPUT" <<EOF
# brain.yaml — ${name} Brain Configuration
#
# This file defines variables used throughout the template.
# Migrated from flat schema to nested schema.
#
# After substitution, this file becomes a read-only record of the
# agent's configuration. Do not delete it.

# ── Deployment ────────────────────────────────────────────────────────────────

deployment:
  mode: "${deployment_mode}"
  parent_repo: ""
  subfolder_path: ""

# ── Agent Identity ────────────────────────────────────────────────────────────

agent:
  name: "${name}"
  id: "${agent_id}"
  branch: ""
  creature: ""
  emoji: ""
  description: "${description}"

# ── Owner ─────────────────────────────────────────────────────────────────────

owner:
  name: "admin"
  timezone: "UTC"
  discord_id: ""
  telegram_id: ""

# ── Platform ──────────────────────────────────────────────────────────────────

platform:
  type: "openclaw"
  workspace_path: ""

# ── Model ─────────────────────────────────────────────────────────────────────

model:
  default: "kimi-coding/k2p5"
  aliases: {}

# ── Memory ────────────────────────────────────────────────────────────────────

memory:
  backend: "${memory_backend_mapped}"
  bank_id: ""
  hindsight_endpoint: ""
  embedding_provider: ""

# ── MCP Servers ───────────────────────────────────────────────────────────────

mcp_servers: []

# ── GitHub ────────────────────────────────────────────────────────────────────

github:
  user: ""
  user_id: ""
  repo: ""

# ── Security ──────────────────────────────────────────────────────────────────

security:
  admin_id: ""
  admin_name: ""

# ── Multi-Agent ───────────────────────────────────────────────────────────────

multi_agent:
  enabled: false
  agents: []

# ── OpenClaw Advanced ─────────────────────────────────────────────────────────

openclaw:
  tools:
    allow: []
    deny: []
  sandbox:
    mode: "off"
  compaction:
    reserve_tokens_floor: 20000
  identity:
    theme: ""
  group_chat:
    mention_patterns: []
  block_streaming: false

# ── Skills ────────────────────────────────────────────────────────────────────
# Agent-specific skills (not in template, preserved from flat schema)

EOF

# Append skills section if any skills exist
if [[ ${#skills[@]} -gt 0 ]]; then
  echo "skills:" >> "$OUTPUT"
  for skill in "${skills[@]}"; do
    echo "  - $skill" >> "$OUTPUT"
  done
fi

echo "Migration complete: $INPUT → $OUTPUT"
echo "  agent_id: $agent_id"
echo "  name: $name"
echo "  deploy_mode: $deploy_mode → deployment.mode: $deployment_mode"
echo "  memory_backend: $memory_backend → memory.backend: $memory_backend_mapped"
echo "  skills: ${#skills[@]} preserved"
