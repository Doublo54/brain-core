# Bootstrap Reference

## Variable Catalog

All `{{var.path}}` placeholders used in template files:

| Variable | Used In | Required | Description |
|----------|---------|----------|-------------|
| `{{agent.name}}` | AGENTS, IDENTITY, RETENTION, TOOLS | Yes | Agent display name |
| `{{agent.id}}` | brain.yaml (auto-derive branch, bank_id) | Yes | Slug ID for configs |
| `{{agent.branch}}` | AGENTS, CONTEXT | Auto | Git working branch (`{id}-live`) |
| `{{agent.creature}}` | IDENTITY | No | Character description |
| `{{agent.emoji}}` | IDENTITY | No | Agent emoji(s) |
| `{{owner.name}}` | AGENTS, USER, RETENTION, SECURITY | Yes | Primary user name |
| `{{owner.timezone}}` | USER | No | User timezone |
| `{{owner.discord_id}}` | USER, SECURITY | No | Discord user ID |
| `{{owner.telegram_id}}` | USER | No | Telegram user ID |
| `{{memory.backend}}` | TOOLS | Auto | Active memory backend |
| `{{memory.bank_id}}` | TOOLS, RETENTION | Auto | Hindsight bank ID |
| `{{memory.hindsight_endpoint}}` | TOOLS | Hindsight only | Hindsight API URL |
| `{{github.user}}` | TOOLS, CONTEXT | No | GitHub username |
| `{{github.user_id}}` | TOOLS | No | GitHub user ID |
| `{{github.repo}}` | TOOLS, CONTEXT | No | Brain repo name |
| `{{security.admin_id}}` | SECURITY | Auto | Admin identifier |
| `{{security.admin_name}}` | SECURITY | Auto | Admin display name |
| `{{date}}` | RETENTION, TOOLS, CONTEXT | Auto | Current date |

## Auto-Derived Values

- `agent.branch` = `"{agent.id}-live"`
- `memory.bank_id` = `agent.id`
- `security.admin_id` = first of: `owner.discord_id`, `owner.telegram_id`, `owner.name`
- `security.admin_name` = `owner.name`
- `date` = current date at substitution time

## Deployment Modes

### Standalone Repo (default)

Full brain as its own git repository:
```
my-agent-brain/
  brain.yaml
  AGENTS.md
  IDENTITY.md
  ...
  memory/
  skills/
```

### Subfolder Within Existing Brain

Agent brain nested inside a parent brain repo:
```
parent-brain/
  SECURITY.md           (shared)
  CONVENTIONS.md        (shared)
  PLAYBOOK.md           (shared)
  agents/
    new-agent/
      brain.yaml
      AGENTS.md
      IDENTITY.md
      CONTEXT.md
      TOOLS.md
      RETENTION.md
      memory/
      skills/           (can use parent's skills or have own)
```

Shared files stay at parent root. Agent-specific files go in the subfolder.
The subfolder path is configurable via `deployment.subfolder_path` in brain.yaml.

## Multi-Agent Directory Convention

### Single Agent (default)

All files at root level:
```
IDENTITY.md
CONTEXT.md
MEMORY.md
memory/
```

### Multiple Agents (within one brain)

Agent-specific files in subdirectories:
```
SECURITY.md         (shared)
CONVENTIONS.md      (shared)
agents/
  primary/
    IDENTITY.md
    CONTEXT.md
    memory/
  secondary/
    IDENTITY.md
    CONTEXT.md
    memory/
```

## OpenClaw Agent Config Reference

All OpenClaw configuration templates are consolidated in [../../config/reference.md](../../config/reference.md).

**Quick links:**
- [Agent Entry](../../config/reference.md#agent-entry) — Essential agent definition
- [Model Aliases](../../config/reference.md#model-aliases) — Short model names
- [Bindings](../../config/reference.md#bindings) — Message routing
- [Tool Policy](../../config/reference.md#tool-policy) — Access control patterns
- [Sandbox](../../config/reference.md#sandbox) — Isolation modes
- [Compaction + Memory Flush](../../config/reference.md#compaction-memory-flush) — Context management
- [Group Chat](../../config/reference.md#group-chat) — Mention patterns
- [LanceDB Plugin](../../config/reference.md#lancedb-plugin) — Auto-capture memory
- [Hindsight-Retain Plugin](../../config/reference.md#hindsight-retain-plugin) — External semantic memory
