---
name: manage-agent
version: 1.0.0
description: "Manage existing agent brains: list agents, health check, update config, archive. Use when asked to check on agents, update an agent's settings, list running agents, or decommission an agent."
---

# Manage Agent

Lifecycle management for agents created via the create-agent skill. All operations read from the agent registry at `knowledge/agents/registry.md`.

For health check details and archive process, see [reference.md](reference.md).

---

## Operations

### List

Read `knowledge/agents/registry.md` and present a summary:
- Active agents with their backend, deployment mode, and last health check
- Archived agents (if any)
- Cross-reference with OpenClaw config (`agents.list`) to flag discrepancies (agent in registry but not in config, or vice versa)

### Health Check

Run for a specific agent or all active agents.

Use tool-native checks first; use CLI only as fallback when equivalent tool access is unavailable.

1. **Workspace**: Verify the workspace directory exists and contains AGENTS.md
2. **Memory backend**:
   - builtin: Check that `memory/` dir exists with recent files
   - lancedb: Verify `OPENAI_API_KEY` is set, check LanceDB dir exists
   - hindsight: Query bank stats (`GET /v1/default/banks/{id}/stats`), verify node count > 0
   - qmd: Check `qmd` binary is available
3. **Config**: Read OpenClaw config, verify agent entry exists with correct workspace path
4. **Connectivity**:
   - Discover target session via `sessions_list` for the agent id
   - If session exists: use `sessions_send` with `"health check"` and verify response
   - If no session exists: fallback to `openclaw agent --agent {id} --message "health check"`
5. **Update registry**: Write last health check date and any issues found

Report results as a checklist with pass/fail for each check.

### Update Config

When asked to change an agent's configuration:

1. Read current config from OpenClaw (`gateway config.get` or config file)
2. Identify what needs to change (model, tools, sandbox, channels, etc.)
3. Generate the config patch
4. **Present the patch and wait for explicit approval**
5. After approval, suggest applying via `gateway config.patch`
6. Update the registry if relevant fields changed (model, workspace, status)

Common update scenarios:
- Change default model
- Add/remove tool restrictions
- Enable/disable sandbox
- Add channel bindings
- Update compaction settings

### Archive

Decommission an agent:

1. **Confirm intent** — require explicit confirmation: "CONFIRM: archive {agent-name}"
2. Remove channel bindings from OpenClaw config (propose, wait for approval)
3. Remove agent entry from `agents.list` (propose, wait for approval)
4. Mark as `archived` in the registry with date
5. **Do NOT delete the workspace or repo** — archive means inactive, not destroyed
6. Optionally: commit and push the brain repo with a final "archived" status in CONTEXT.md

---

## Safety

- All config changes require explicit human approval
- Archive never deletes data — only removes config bindings
- Health check is read-only and always safe to run
- Flag but don't auto-fix discrepancies between registry and config
