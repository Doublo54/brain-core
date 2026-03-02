# brain-core

Reusable deployment infrastructure for running an [OpenClaw](https://github.com/openclaw/openclaw) gateway on Coolify/Hetzner with Docker-outside-of-Docker (DooD) sandbox support.

This repo is a **standalone starting point** — completely decoupled from any specific agent's brain files. Clone it, set your environment variables, deploy to Coolify, and you have a working OpenClaw gateway with sandboxed agent support.

---

## Quick Start

1. **Clone this repo** and point your Coolify resource at it
2. **Set environment variables** in Coolify (minimum: `OPENCLAW_GATEWAY_TOKEN` + at least one API key)
3. **Deploy** — the entrypoint auto-generates `openclaw.json` on first boot from the config template
4. **Customize** post-deploy via Coolify Terminal or `openclaw config.patch`

See [docs/deployment.md](docs/deployment.md) for the full step-by-step runbook.

---

## What's Inside

```
brain-core/
├── docker/                          # Docker infrastructure
│   ├── Dockerfile                   # Multi-stage: gateway + sandbox targets
│   ├── docker-compose.coolify.yml   # Coolify compose (4 services)
│   └── entrypoint.sh               # Hook-based gateway entrypoint
├── config/                          # Configuration (baked into image)
│   ├── openclaw.json.template       # envsubst template, auto-applied on first boot
│   └── mcporter.json                # MCP server config (env var refs, no secrets)
├── scripts/                         # Runtime scripts (baked into image)
│   ├── bootstrap-opencode.sh        # OpenCode/OHO persistent setup
│   ├── orchestration/               # Orchestration scripts for multi-agent environments
│   │   ├── task-manager.sh          # Task lifecycle management
│   │   ├── execute-task.sh          # Task execution with approval gates
│   │   ├── opencode-session.sh      # OpenCode session orchestration
│   │   ├── github-pr.sh             # GitHub PR automation
│   │   ├── setup-workspace.sh       # Workspace initialization
│   │   ├── cleanup-workspace.sh     # Workspace cleanup
│   │   ├── daemon-monitor.sh        # Daemon health monitoring
│   │   ├── monitor.sh               # Session monitoring
│   │   ├── test-orchestrator.sh     # Test orchestration
│   │   ├── test-approval-gate.sh    # Approval gate testing
│   │   └── templates/               # Script templates for code generation
│   └── hooks/                       # Example entrypoint hooks
├── integrations/                    # Integrations with external services
│   └── opencode-discord-pipe/       # Discord streaming daemon for OpenCode sessions
│       ├── daemon.sh                # Daemon startup script
│       ├── pipe.ts                  # Session output streaming
│       ├── formatter.ts             # Discord message formatting
│       ├── discord.ts               # Discord API client
│       └── README.md                # Integration documentation
├── docs/                            # Operational documentation
│   ├── deployment.md                # Full deployment runbook
│   ├── dood-path-mapping.md         # Workspace path resolution for DooD sandboxes
│   ├── security-model.md            # Trust boundaries and network isolation
│   ├── orchestration-scripts.md     # Orchestration scripts reference
│   └── orchestration/               # Orchestration system documentation
│       └── architecture.md          # Complete orchestration architecture
├── skills/                          # Agent lifecycle skills (for AI agents)
│   ├── core/                        # Operational skills for agent lifecycle
│   │   ├── create-agent/            # Create new agent brains
│   │   ├── manage-agent/            # Health checks, config updates, archival
│   │   └── upgrade-agent/           # Apply template updates to existing agents
│   ├── behavioral/                  # Skills copied into every agent brain
│   │   ├── memory-brain/            # Memory management and persistence
│   │   └── proactive-agent-behavior/# Proactive behavior patterns
│   └── specialized/                 # Optional domain-specific skills
│       ├── coding-orchestrator/     # Code generation and orchestration
│       └── code-review-orchestrator/# Code review automation
└── template/                        # Agent brain template (copied for new agents)
```

---

## Architecture

The deployment runs as a Docker Compose stack managed by Coolify:

- **openclaw** — Gateway process. Manages agent sessions, connects to Docker proxy for sandbox lifecycle.
- **docker-proxy** — Filtered Docker socket proxy. Only allows container/exec/image/network endpoints.
- **sandbox-builder** — Init container. Builds and tags the sandbox image, then exits.
- **workspace-init** — Init container. Sets volume permissions (uid 1000), then exits.

Sandbox containers are spawned as **DooD siblings** on the host Docker daemon. They join `rag-network` (can reach Hindsight) but cannot reach the Docker proxy.

See [docs/security-model.md](docs/security-model.md) for the full trust model.

---

## Orchestration Scripts

The `scripts/orchestration/` directory contains 14 battle-tested scripts for:

- **Task management** — `task-manager.sh`, `execute-task.sh` for task lifecycle and execution
- **Session orchestration** — `opencode-session.sh`, `monitor.sh` for OpenCode session management
- **GitHub integration** — `github-pr.sh`, `setup-workspace.sh`, `cleanup-workspace.sh` for PR automation
- **Daemon monitoring** — `daemon-monitor.sh`, `watchdog` scripts for health checks
- **Testing** — `test-orchestrator.sh`, `test-approval-gate.sh` for orchestration validation

Scripts are baked into the Docker image at `/opt/scripts/orchestration/` and designed for multi-agent environments with per-agent workspace isolation.

See [docs/orchestration-scripts.md](docs/orchestration-scripts.md) for the complete script reference and [docs/orchestration/architecture.md](docs/orchestration/architecture.md) for the orchestration system design.

---

## Discord Pipe Integration

The `integrations/opencode-discord-pipe/` directory contains a TypeScript daemon that streams OpenCode session output to Discord channels in real-time. Baked into the Docker image at `/opt/integrations/opencode-discord-pipe/`.

Features:
- Real-time session output streaming to Discord
- Formatted message rendering with code blocks and embeds
- Daemon health monitoring and auto-restart
- Configurable channel routing and message filtering

See [integrations/opencode-discord-pipe/README.md](integrations/opencode-discord-pipe/README.md) for architecture, configuration, and usage.

---

## Configuration

### Environment Variables

All configuration is done through Coolify environment variables. The config template uses `envsubst` on first boot to generate `openclaw.json`.

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Yes | Gateway auth token |
| `BRAIN_HOST_PATH` | For sandbox | Host-absolute path to the brain workspace (required for sandbox agents) |
| `OPENCLAW_DEFAULT_MODEL` | No | Default model (default: `anthropic/claude-sonnet-4-5`) |
| `OPENCLAW_AGENT_NAME` | No | Main agent display name (default: `Agent`) |
| `OPENCLAW_USER_TIMEZONE` | No | Timezone (default: `UTC`) |
| `ANTHROPIC_API_KEY` | Recommended | Anthropic API key |
| `ZAI_API_KEY` | Recommended | Powers 3 MCP servers (zai-vision, web-reader, zread) |

See [docs/deployment.md](docs/deployment.md) for the complete variable reference.

### MCP Servers

Five MCP servers are pre-configured in `config/mcporter.json` and work out of the box when their corresponding API keys are set:

| Server | API Key Required |
|--------|-----------------|
| hindsight | Hindsight service on rag-network |
| zai-vision | `ZAI_API_KEY` |
| web-reader | `ZAI_API_KEY` |
| zread | `ZAI_API_KEY` |
| clickup | `CLICKUP_API_KEY` |

### Entrypoint Hooks

Custom startup logic (OpenCode server, Discord pipe daemon, etc.) is supported via hook scripts placed in `/home/node/.openclaw/hooks/`. See [scripts/hooks/README.md](scripts/hooks/README.md) for the contract.

---

## Creating New Agents

Use the `skills/core/create-agent/` skill to spawn new agent brains from the `template/` directory. The skill handles:

- Repository/workspace setup from template
- Variable substitution and identity bootstrapping
- OpenClaw config generation (with approval gates)
- Memory backend configuration
- Verification and registry

See [skills/core/create-agent/SKILL.md](skills/core/create-agent/SKILL.md) for the full workflow.

---

## Key Documentation

| Document | What it covers |
|----------|---------------|
| [deployment.md](docs/deployment.md) | Full deployment runbook, env vars, verification, troubleshooting |
| [dood-path-mapping.md](docs/dood-path-mapping.md) | How sandbox workspace paths resolve through DooD + Coolify volumes |
| [security-model.md](docs/security-model.md) | Trust boundaries, socket proxy, what agents can/cannot do |

---

## Deprecation Notice

The template is now maintained as `brain-core/template/`. All new agents should be created from this local copy.

---

## Testing

### Test Infrastructure

brain-core uses two testing frameworks:

- **BATS** (Bash Automated Testing System) for bash script testing
- **vitest** for TypeScript testing

### Running Tests

**BATS tests** (bash scripts):
```bash
# Run all BATS tests
bats brain-core/scripts/orchestration/tests/

# Run specific test file
bats brain-core/scripts/orchestration/tests/task-manager.bats
```

**vitest tests** (TypeScript):
```bash
# Run all vitest tests
cd brain-core && npm test

# Run in watch mode
cd brain-core && npm run test:watch
```

### Test Conventions

**BATS tests:**
- Located in `scripts/orchestration/tests/*.bats`
- Test bash scripts for basic functionality and integration
- Use temporary workspaces for isolation
- Require bash 5+ (install via Homebrew: `brew install bash`)
- Require flock (install via Homebrew: `brew install flock`)

**vitest tests:**
- Colocated with source files as `*.test.ts`
- Test pure functions and module behavior
- Use `vi.mock()` for dependencies that have side effects
- Follow existing test patterns in `plugins/telegramuser/src/` (drafts.test.ts, send-utils.test.ts)

**Example test locations:**
- `scripts/orchestration/tests/task-manager.bats` — BATS test for task-manager.sh
- `integrations/opencode-discord-pipe/formatter.test.ts` — vitest test for formatter.ts

---

## What Does NOT Belong Here

This repo is infrastructure + reusable orchestration tooling. Do not add:

- Agent identity files with real content (IDENTITY.md, SOUL.md, etc.)
- Knowledge directories (knowledge/)
- Memory files (memory/)
- Real `openclaw.json` with tokens or user IDs
- Organization-specific configurations
