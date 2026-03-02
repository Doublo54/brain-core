# OpenCode Security Policies

## Workspace Isolation

OpenCode sessions are sandboxed to `/opt/opencode/`:

```
/opt/opencode/
├── default/          # Default workspace (sessions without specific project)
│   ├── AGENTS.md     # Per-project agent rules
│   └── opencode.json # Project-level OpenCode config
├── projects/         # Cloned repos and project workspaces
├── sandbox/          # Temporary/experimental files
└── oho-test/         # OHO integration testing
```

### Forbidden Directories

OpenCode agents must NEVER access:
- `/app/` — OpenClaw application code
- `/home/node/.openclaw/` — OpenClaw config and workspace
- `/home/node/.config/` — User configuration (except opencode config)
- System directories (`/etc/`, `/usr/`, etc.)

### Enforcement Layers

1. **AGENTS.md** (global + per-project) — Instructions to the model
2. **Session directory** — Always set to `/opt/opencode/default` or a specific project
3. **OHO orchestrator** (Phase 3) — Will enforce workspace selection on session creation

### When Creating Sessions

Always specify the directory:
```bash
# Via API
curl -X POST "http://localhost:4096/session" \
  -d '{"projectID":"global","directory":"/opt/opencode/default"}'

# Via OHO
oh-my-opencode run --directory /opt/opencode/default "task description"
```

## Model Access

OpenCode agents have access to various models via Antigravity/providers.
Cost awareness: All token usage is tracked and reported via the pipe to Discord.

## Network

- OpenCode server: `localhost:4096` (internal only)
- Agents should not access other internal services unless explicitly instructed.
