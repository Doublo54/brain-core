# Agent Brain Template

A batteries-included template for creating AI agent "brains" — the workspace, memory, identity, and behavioral framework that make an agent persistent and personal.

Built on top of [OpenClaw](https://github.com/openclaw/openclaw)'s workspace conventions, but designed to work with any AI agent platform (Cursor, Claude Code, generic).

## What's in the box

- **Identity system** — SOUL.md, IDENTITY.md, USER.md define who the agent is, what it values, and who it serves
- **Memory architecture** — File-based memory with support for 4 semantic backends (built-in, LanceDB, QMD, Hindsight)
- **Behavioral skills** — Proactive agent behavior, WAL protocol, self-healing, reverse prompting, pattern recognition
- **Memory management skill** — Dual-layer memory (files + RAG), retention rules, context taxonomy
- **Security hardening** — Admin verification, destructive operation guards, prompt injection defense
- **Multi-agent support** — Single or multi-agent layouts from day one
- **Interactive bootstrap** — A skill that walks you (or your AI) through setup conversationally

## Quick start

### Option 1: Clone and bootstrap manually

```bash
git clone https://github.com/YOUR_USER/agent-brain.git my-agent-brain
cd my-agent-brain

# Edit brain.yaml with your values, then:
bash bootstrap/substitute.sh
```

### Option 2: Subfolder within an existing brain

```bash
# From your existing brain repo:
cp -r /path/to/agent-brain-template agents/new-agent/
# Then bootstrap from within the subfolder
```

## Deployment modes

| Mode | Use case |
|------|----------|
| **Standalone repo** | Primary agents, independent brains with their own git history |
| **Subfolder** | Secondary agents managed within a primary brain repo (e.g., `agents/worker/`) |

## Memory backends

| Backend | Complexity | Auto-capture | Needs |
|---------|-----------|--------------|-------|
| **Built-in** | Zero config | No | Nothing |
| **LanceDB** | One setting | Yes | OpenAI API key |
| **QMD** | Moderate | No | QMD CLI |
| **Hindsight** | High | Yes (plugin) | Hindsight service |

See [plugins/README.md](plugins/README.md) for detailed setup and comparison.

## File map

```
brain.yaml              # Agent configuration (variables + choices)
AGENTS.md               # Workspace rules (loaded every session)
SOUL.md                 # Principles and boundaries
IDENTITY.md             # Agent persona and roles
USER.md                 # Human profile
CONTEXT.md              # Active working state
TOOLS.md                # Tool configs and memory backend docs
SECURITY.md             # Admin verification and operation guards
RETENTION.md            # Memory retention rules and naming conventions
MEMORY.md               # Curated long-term memory (private, main session only)
LEARNINGS.md            # Lessons learned (agent-maintained)

CONVENTIONS.md          # File lifecycle and naming standards
PLAYBOOK.md             # Group chat behavior and heartbeat guidance
HEARTBEAT.md            # Periodic task checklist (empty by default)
CONFIG_BACKUP.md        # OpenClaw config backup process
BOOT.md                 # OpenClaw gateway restart checklist
BOOTSTRAP.md            # First-run ritual (delete after first session)

bootstrap/              # Bootstrap skill + tools (delete after setup)
  SKILL.md              # Interactive onboarding (Cursor + OpenClaw)
  substitute.sh         # Variable replacement script
  reference.md          # Variable catalog and multi-agent docs

skills/                 # Behavioral frameworks
  memory-brain/         # Memory management skill
  proactive-agent-behavior/  # Proactive behavior skill

plugins/                # Memory backend documentation
  README.md             # All 4 memory tiers + MCP server catalog

memory/                 # Daily logs go here
```

## After bootstrap

1. Your agent reads CONTEXT.md, IDENTITY.md, SOUL.md at session start
2. It creates daily memory files in `memory/`
3. Review and personalize IDENTITY.md and SOUL.md — the agent drafts, you own
4. Add org/team knowledge to `knowledge/` if needed
5. Start talking to your agent

## Credits

Derived from a production AI agent running on OpenClaw. Skills, behavioral frameworks, and memory architecture developed through months of real-world use.

- Hindsight-retain plugin: [{github-org}/openclaw-hindsight-retain](https://github.com/{github-org}/openclaw-hindsight-retain) (replace `{github-org}` with your organization's GitHub org)

## License

MIT
