---
name: create-agent
version: 2.0.0
description: "Create new agent brains from the brain-core template. Handles repo setup, bootstrap, OpenClaw config generation, memory backend, verification, and registry. Use when asked to create a new agent, set up a new brain, or spawn a new persona."
---

# Create Agent

Spawn a new agent brain from the `template/` directory in this brain-core repo. Propose changes, never auto-apply config.

For config templates, API details, and troubleshooting, see [reference.md](reference.md).

---

## Fast Path (Common Case)

Use this when user wants a standard OpenClaw agent with minimal customization.

1. **Select role template** — Ask "What role will this agent fill?" Present the template catalog from `brain-core/role-templates/`. If user doesn't know, suggest based on their description.
2. Gather required fields: `id`, `name`, channel/account binding. (Most fields now come from role template defaults)
3. Create from template + merge role defaults.
4. Bootstrap + substitute variables.
5. Propose **Essentials-only** OpenClaw config patch.
6. Run verification checklist.
7. Register in `knowledge/agents/registry.md`.

If any non-standard requirement appears (custom sandbox, custom tool policy, multi-channel routing, non-OpenClaw platform), switch to full workflow below.

## Workflow

### 1. Gather

Ask conversationally.

**Role Template Selection:**
- Present available roles from `brain-core/role-templates/`: orchestrator, coding, chief-of-staff, sales, finance, community-lead, marketing
- Show each role's one-line description (from brain.yaml.defaults)
- Selected role provides defaults for: skills, MCP servers, memory backend, sandbox mode, tier
- User can override any default during creation

Minimum:
- **Name and purpose** — what will this agent do?
- **Deployment** — standalone repo or subfolder in an existing brain?
- **Platform** — openclaw, cursor, or generic?
- **Memory backend** — builtin, lancedb, qmd, or hindsight?
- **Default model** — suggest `kimi-coding/k2p5`, ask if they want different

Also collect: owner name, timezone, channel IDs, GitHub user, agent character/emoji. Skip what's obvious from context.

### 2. Create

**Standalone:** Copy the template from `brain-core/template/` into a new private GitHub repo. Create the repo via the GitHub REST API (`GITHUB_TOKEN` required), then push the template contents. See [reference.md](reference.md) for the API call.

**Subfolder:** Copy the template from `brain-core/template/` into `agents/{id}/` within the parent brain. Remove shared files (SECURITY.md, CONVENTIONS.md, PLAYBOOK.md) — those stay at parent root. The subfolder gets its own skills/ and plugins/.

**Role Template Merge:**
After copying base template, merge role-specific files:
1. Copy `brain-core/role-templates/{role}/IDENTITY.md` → agent's IDENTITY.md (as scaffold)
2. Copy `brain-core/role-templates/{role}/PLAYBOOK.md` → agent's PLAYBOOK.md
3. Copy `brain-core/role-templates/{role}/knowledge/role-guide.md` → agent's knowledge/
4. Merge `brain-core/role-templates/{role}/brain.yaml.defaults` values into brain.yaml
5. Set `template_version` from the role template's brain.yaml.defaults

**Skills:** After copying the template, install skills from brain-core:
- **Behavioral skills** (always copied): `skills/behavioral/memory-brain/`, `skills/behavioral/proactive-agent-behavior/` — every agent needs memory and proactive behavior.
- **Specialized skills** (optional, via `--skills` flag): Pass `--skills coding-orchestrator,code-review-orchestrator` to include domain-specific skills from `brain-core/skills/specialized/`. Only copy the ones the agent needs.

Example: `create-agent --skills coding-orchestrator` copies `skills/specialized/coding-orchestrator/` into the new agent's `skills/specialized/` directory.

### 3. Bootstrap

1. Write gathered values to `brain.yaml`
2. Run `bootstrap/substitute.sh` for mechanical `{{var}}` replacements
3. Make contextual edits:
   - **TOOLS.md**: Write only the active memory backend's docs (pull from `plugins/README.md`)
   - **IDENTITY.md**: Draft real content for Core Philosophy, Roles, Personas from the conversation
   - **AGENTS.md**: Remove inapplicable memory references
   - **RETENTION.md**: Simplify if not using Hindsight
   - Remove OpenClaw-specific files if platform is not OpenClaw (CONFIG_BACKUP.md, BOOT.md)

### 4. Memory Setup

#### Memory Architecture: 3-Layer Design

OpenClaw's memory system uses three independent layers that can coexist simultaneously:

1. **Layer 1: memorySearch (always on, file-based)** — Built-in hybrid BM25+vector search over `memory/` directory and `MEMORY.md`. Zero config required. Enabled by default via `memorySearch.enabled: true` in `openclaw.json`.

2. **Layer 2: Memory Slot (`plugins.slots.memory`)** — Pluggable backend for auto-capture and auto-recall. Choose ONE:
   - **builtin** (default): No additional config
   - **lancedb**: Requires `OPENAI_API_KEY` and config snippet in `openclaw.json`
   - **qmd**: Requires QMD CLI installed and config snippet in `openclaw.json`
   
   These are **mutually exclusive** — pick one slot backend per agent.

3. **Layer 3: Hindsight (`plugins.entries.hindsight-retain`)** — Standalone semantic memory with named banks and cross-agent sharing. Can run alongside ANY Layer 2 choice. Requires:
   - Hindsight service deployed
   - Plugin installed as git submodule: `git submodule add https://github.com/{github-org}/openclaw-hindsight-retain.git .openclaw/plugins/hindsight-retain`
   - Config in `openclaw.json` with `apiUrl`, `bankId`, `assistantName`
   - **Critical**: When user picks Hindsight, add the new agent's ID to the `agentIds` array in `plugins.entries.hindsight-retain.config` in `openclaw.json`. Without this, the plugin ignores the agent.

**Configuration Separation:**
- **brain.yaml** = Intent layer (what the agent is, skills, defaults, identity)
- **openclaw.json** = Runtime layer (where plugins live, how they're configured, agent-specific overrides)

This separation is intentional: brain.yaml is portable across platforms; openclaw.json is platform-specific.

**Backend-Specific Behavioral Instructions:**
During Step 3 (Bootstrap), write backend-specific docs to `TOOLS.md` by pulling from `plugins/README.md`. This ensures the agent knows how to use its configured memory backend.

#### Backend Actions

| Backend | Action |
|---------|--------|
| builtin | Nothing — enabled by default |
| lancedb | Note config snippet for `openclaw.json`. Remind about `OPENAI_API_KEY` |
| qmd | Note config snippet. Remind to install QMD CLI |
| hindsight | Create bank via Hindsight API. Add submodule: `{github-org}/openclaw-hindsight-retain` (replace `{github-org}` with your organization's GitHub org). Generate mcporter.json. **Add agent ID to `agentIds` array in `plugins.entries.hindsight-retain.config` in `openclaw.json`** — without this, the plugin ignores the agent. |

### 5. MCP Servers

Start with zero. Present available servers (see [reference.md](reference.md) for catalog). User picks which to enable. Generate `config/mcporter.json` from selections. Auto-include hindsight MCP if hindsight backend chosen.

### 6. OpenClaw Config (if platform = openclaw)

Generate config in two stages. **Wait for approval on each.**

**Essentials:**
- Agent entry (`id`, `name`, `workspace`, `model`, `skipBootstrap: true`, `identity`)
- Model aliases if requested
- Channel binding (ask which channel/account)

**Advanced** (offer category by category):
- Tool policy (allow/deny)
- Sandbox mode
- Compaction settings
- Group chat mention patterns
- Block streaming

See [reference.md](reference.md) for all config templates.

### 7. Git + Deploy

**Standalone repo:**
- Initialize git only if not already inside a repo (`git rev-parse --is-inside-work-tree`)
- Create working branch (`{id}-live`)
- Initial commit, push to remote
- Clean up: remove `bootstrap/`, `META_AGENT_ASSESSMENT.md`

**Subfolder in existing brain repo:**
- NEVER run `git init` — the parent repo tracks this directory
- Stage the new agent directory and commit to the parent repo's working branch
- Clean up: remove `bootstrap/`, `META_AGENT_ASSESSMENT.md`

### 8. Verify

Run these checks and report results:

- [ ] Workspace directory exists
- [ ] If Hindsight: bank responds to stats query
- [ ] If LanceDB: `OPENAI_API_KEY` env var is set
- [ ] OpenClaw config includes the agent entry (read via `gateway config.get` or config file)
- [ ] Connectivity check (prefer in this order):
  1. Discover target session via `sessions_list` for this agent id.
  2. If a session exists: use `sessions_send` with `"health check"` and verify a response.
  3. If no session exists: use `openclaw agent --agent {id} --message "health check"` (CLI fallback).
- [ ] Report pass/fail for each check

### 9. Register

Add the new agent to `knowledge/agents/registry.md` in this brain repo:

```
| {id} | {name} | {date} | {template_version} | {backend} | {mode} | {workspace} | {repo-url} | active | {date} |
```

Commit the registry update.

---

## Safety

- **NEVER** apply OpenClaw config without explicit approval
- **NEVER** create public repos
- **NEVER** commit secrets
- If any step fails, stop and report — don't retry destructive operations
