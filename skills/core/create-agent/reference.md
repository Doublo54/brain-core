# Create Agent — Reference

Config templates, API details, MCP catalog, and troubleshooting. Read when you need specifics during agent creation.

---

## Template Source

- **Primary:** `brain-core/template/` directory (local copy, always up to date)
- **Hindsight plugin:** https://github.com/{github-org}/openclaw-hindsight-retain (replace `{github-org}` with your organization's GitHub org)

---

## Role Templates

Role templates provide pre-configured identities, playbooks, and skill/MCP defaults for specific agent personas.

### Template Catalog

| Role | Description | Default Skills | Default MCPs |
|------|-------------|----------------|--------------|
| `orchestrator` | High-level task management and delegation | `coding-orchestrator` | `hindsight`, `clickup` |
| `coding` | Software development and code review | `coding-orchestrator`, `code-review` | `zread`, `zai-vision` |
| `chief-of-staff` | Executive support and scheduling | `proactive-behavior` | `google-workspace`, `clickup` |
| `sales` | Lead generation and outreach | `marketing-outreach` | `web-reader`, `clickup` |
| `finance` | Budgeting and financial analysis | `data-analysis` | `google-workspace` |
| `community-lead` | Discord/Telegram community management | `community-engagement` | `discord-roles` |
| `marketing` | Content creation and social media | `content-strategy` | `web-reader`, `zai-vision` |

### Role Template Merge Example

When creating a `coding` agent, the following merge occurs:

1. **Identity:** `role-templates/coding/IDENTITY.md` is used as the starting point for the agent's identity.
2. **Playbook:** `role-templates/coding/PLAYBOOK.md` is copied to the agent's root.
3. **Knowledge:** `role-templates/coding/knowledge/role-guide.md` is added to the agent's `knowledge/` directory.
4. **Config:** `role-templates/coding/brain.yaml.defaults` values (e.g., `memory.backend: lancedb`) are merged into the agent's `brain.yaml`.
5. **Version:** `template_version` is set to the version specified in the role's defaults.

---

Skills in brain-core are organized into three tiers:

| Tier | Path | Copied to Agent? | Purpose |
|------|------|-------------------|---------|
| **Core** | `skills/core/` | No (stays in brain-core) | Agent lifecycle operations: create, upgrade, manage agents |
| **Behavioral** | `skills/behavioral/` | Always | Behaviors every agent needs: memory management, proactive behavior |
| **Specialized** | `skills/specialized/` | Optional (via `--skills`) | Domain-specific capabilities: coding orchestration, code review |

### Behavioral Skills (Always Installed)

These are copied into every new agent brain during creation:

- `skills/behavioral/memory-brain/` — Memory persistence, daily logs, context management
- `skills/behavioral/proactive-agent-behavior/` — Proactive behavior patterns, initiative triggers

### Specialized Skills (Optional)

Installed only when requested via `--skills` parameter:

- `skills/specialized/coding-orchestrator/` — OpenCode session management, task lifecycle, GitHub PR automation
- `skills/specialized/code-review-orchestrator/` — Code review automation and orchestration

**Usage:** `create-agent --skills coding-orchestrator,code-review-orchestrator`

---

## OpenClaw Config Templates

All OpenClaw configuration templates are consolidated in [config/reference.md](../../config/reference.md).

**Quick links:**
- [Agent Entry](../../config/reference.md#agent-entry) — Basic agent definition
- [Model Aliases](../../config/reference.md#model-aliases) — Short aliases for models
- [Bindings](../../config/reference.md#bindings) — Route messages to agents
- [Tool Policy](../../config/reference.md#tool-policy) — Control tool access
- [Sandbox](../../config/reference.md#sandbox) — Docker isolation modes
- [Compaction + Memory Flush](../../config/reference.md#compaction-memory-flush) — Context management
- [Group Chat](../../config/reference.md#group-chat) — Mention patterns
- [LanceDB Plugin](../../config/reference.md#lancedb-plugin) — Auto-capture memory
- [Hindsight-Retain Plugin](../../config/reference.md#hindsight-retain-plugin) — External semantic memory

---

## MCP Server Catalog

See [config/reference.md#mcp-server-catalog](../../config/reference.md#mcp-server-catalog) for the complete catalog of pre-configured MCP servers (hindsight, zai-vision, web-reader, zread, clickup) with setup instructions and authentication details.

---

## Hindsight Bank API

### Create bank

```
PUT /v1/default/banks/{agent-id}
{
  "name": "{agent-name}",
  "mission": "{from IDENTITY.md}",
  "disposition": { "skepticism": 3, "literalism": 3, "empathy": 3 }
}
```

### Verify bank

```
GET /v1/default/banks/{agent-id}/stats
```

### Disposition guidelines

| Agent Role | Skepticism | Literalism | Empathy |
|---|---|---|---|
| Code Reviewer | 4-5 | 4 | 2 |
| Personal Assistant | 2 | 2 | 4-5 |
| Issue Triager | 3 | 3 | 3 |
| Orchestrator | 3 | 3 | 3 |

---

## Runtime Compatibility Notes

- Prefer OpenClaw tools (`gateway`, `sessions_*`, `memory_*`) when available in the runtime.
- Use CLI commands (`openclaw ...`) only as fallback or when explicitly required.
- For connectivity checks: discover session via `sessions_list`; if found, use `sessions_send`; if not, use `openclaw agent --agent ...` fallback.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| GitHub generate API fails | Check `GITHUB_TOKEN` is set, verify template repo is accessible, fall back to manual clone |
| substitute.sh fails on macOS | Ensure running with system bash (`/bin/bash`), not zsh |
| Hindsight bank creation 404 | Verify endpoint URL, ensure Hindsight service is running |
| Agent doesn't respond after config | Check binding matches, verify `skipBootstrap: true` |
| Memory search returns nothing | Verify memory files exist in `memory/`, check memorySearch.enabled |
| LanceDB auto-capture not working | Verify `plugins.slots.memory = "memory-lancedb"` and OPENAI_API_KEY set |
| Template files still have `{{var}}` | Re-run substitute.sh or check brain.yaml for missing values |

---

## Registry Format

Each row in `knowledge/agents/registry.md`:

```
| ID | Name | Created | Template Version | Memory | Deploy Mode | Workspace | Repo | Status | Last Health |
```
