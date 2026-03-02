---
name: agent-brain-bootstrap
version: 2.0.0
description: "Interactive bootstrap skill for new agent brains. Walks through onboarding, fills brain.yaml, runs variable substitution, does contextual file edits, and initializes git. Works in Cursor and OpenClaw."
---

> **Role Templates**: If this agent was created with a role template (via create-agent skill),
> many of these phases will have pre-filled defaults from the role template. The bootstrap
> skill should present these defaults and let the user confirm or override.

# Agent Brain Bootstrap

This skill guides you through setting up a new agent brain from the template. It's designed to be run conversationally — ask questions, explain trade-offs, let the user make choices. After setup, delete the `bootstrap/` directory.

---

## Phase 1: Deployment Mode

Ask the user which deployment pattern they want:

**Standalone repo** (default):
- This brain becomes its own git repository
- Clean separation, independent git history
- Best for: primary agents, agents that need full autonomy

**Subfolder within existing brain repo**:
- This brain lives under `agents/{id}/` in a parent brain repo
- Shares git history and PR workflow with the parent
- Best for: secondary agents managed by a primary agent
- Ask for the parent repo path

Write choice to `brain.yaml` under `deployment.mode`.

For **subfolder mode**: the template files get placed under the subfolder path instead of root. Shared files (SECURITY.md, CONVENTIONS.md, PLAYBOOK.md) stay at the parent root and are NOT duplicated.

---

## Phase 2: Core Identity

Ask conversationally. Skip questions where the answer is obvious from context.

### Required
1. **Agent name** — What should this agent be called?
2. **Agent ID** — Auto-derive: lowercase, no spaces, hyphens ok
3. **Owner name** — Who is the primary human?

### Platform
4. **Platform** — Where will this agent run?
   - `openclaw` — Full OpenClaw gateway with channels, tools, and plugins
   - `cursor` — Cursor IDE with AGENTS.md workspace rules
   - `generic` — Other platform or multi-platform

### Optional identity
5. **Owner timezone** (default: UTC)
6. **Owner Discord ID** (if using Discord channels)
7. **Owner Telegram ID** (if using Telegram)
8. **GitHub username** (for repo setup)
9. **Agent character/creature** — Any persona description?
10. **Agent emoji** — Representative emoji(s)?

Write all values to `brain.yaml`.

---

## Phase 3: Model Selection

### Default model
Present the suggestion: `kimi-coding/k2p5` as the recommended default.

Ask if the user wants a different default model. Common options:
- `kimi-coding/k2p5` — recommended default
- `anthropic/claude-opus-4-6` — best for long-context and prompt-injection resistance
- `anthropic/claude-sonnet-4-5` — good balance of cost and capability
- `openai/gpt-5.2` — strong reasoning
- Custom model string

### Aliases
Offer to set up model aliases for convenience. Examples:
```yaml
aliases:
  opus: "anthropic/claude-opus-4-6"
  sonnet: "anthropic/claude-sonnet-4-5"
  k2: "kimi-coding/k2p5"
```

Write to `brain.yaml` under `model.default` and `model.aliases`.

---

## Phase 4: Memory Backend

Present the four tiers with trade-offs. See `plugins/README.md` for full details.

> **Built-in** (default): Zero config. Indexes your memory files with hybrid search. You write notes, it finds them.
>
> **LanceDB**: One config line + OpenAI API key. Automatically captures preferences, facts, and decisions from conversations and recalls them before each turn.
>
> **QMD**: Experimental local-first search sidecar with reranking. Needs the QMD CLI installed.
>
> **Hindsight**: Full semantic memory with named banks, retain/recall/reflect, and cross-agent sharing. Needs a Hindsight service.

Write choice to `brain.yaml` under `memory.backend`.

If **hindsight** selected:
- Ask for Hindsight endpoint URL
- Auto-derive bank_id from agent.id
- Document submodule install step for the plugin (see plugins/README.md Tier 4)

---

## Phase 5A: Communication Channels

Present available channel plugins:

| Plugin | What it does | Needs |
|--------|-------------|-------|
| `discord` (built-in) | Discord bot integration, DM and group channels | Discord bot token |
| `telegramuser` | Telegram personal account via GramJS | API ID, API Hash, String Session |
| `discord-roles` | Discord role management tools | Discord bot token |

Ask which to enable. Record in brain.yaml.

## Phase 5B: Memory Plugins

Based on memory backend selection from Phase 4:

| Plugin | When to Use | Needs |
|--------|------------|-------|
| `hindsight-retain` | If Hindsight backend selected | Hindsight service |

Auto-include hindsight-retain if hindsight backend was chosen.

## Phase 5C: MCP Server Selection

Start with zero MCPs. Present available options:

| Server | What it does | Needs |
|--------|-------------|-------|
| `hindsight` | Semantic memory (retain/recall/reflect) | Hindsight service |
| `zai-vision` | Image/video analysis, OCR | ZAI_API_KEY |
| `web-reader` | Structured web page extraction | ZAI_API_KEY |
| `zread` | Research GitHub repos without cloning | ZAI_API_KEY |
| `clickup` | Project management (tasks, docs, time) | CLICKUP_API_KEY |
| `google-workspace` | Google Workspace (Drive, Sheets, Docs, Gmail, Calendar) | Google OAuth (GOOGLE_WORKSPACE_CLIENT_ID, GOOGLE_WORKSPACE_CLIENT_SECRET, GOOGLE_WORKSPACE_EMAIL) |

If a role template was selected, pre-check the MCP servers recommended for that role. User can uncheck any.

---

## Phase 6: Variable Substitution (Hybrid)

This phase has two parts:

### Part A: Mechanical substitution
Run `bootstrap/substitute.sh` (or do it inline if shell is unavailable). This handles all `{{var.path}}` placeholder replacements across:
- Core files: AGENTS.md, IDENTITY.md, USER.md, SECURITY.md, RETENTION.md, TOOLS.md, CONTEXT.md, MEMORY.md, LEARNINGS.md
- Skills: skills/behavioral/memory-brain/SKILL.md, skills/behavioral/proactive-agent-behavior/SKILL.md

### Part B: Contextual edits (agent-driven)

**This part requires an AI agent.** If bootstrapping manually without an agent, perform these edits by hand.

After mechanical substitution, make these intelligent edits:

1. **TOOLS.md** — Write the active memory backend's documentation into the Memory Backend section. Use the matching content from `plugins/README.md` (the relevant tier). Also populate the MCP Servers section from the selections in Phase 5. Delete the HTML comments.

2. **IDENTITY.md** — Based on the conversation so far, fill in the Core Philosophy, Roles, and Context-Aware Personas sections with actual content (not just comment placeholders). Ask the user if the draft looks right.

3. **AGENTS.md** — If memory backend is NOT hindsight, remove the Hindsight-specific line from the Semantic Memory section. Adjust the "When to Retain" section based on what retention tools are actually available.

4. **RETENTION.md** — If NOT using hindsight, simplify to file-only retention guidance. Remove Hindsight-specific context taxonomy entries that don't apply.

5. **CONFIG_BACKUP.md** — If platform is NOT openclaw, delete this file entirely (it only applies to OpenClaw).

6. **PLAYBOOK.md** — If platform is NOT openclaw, remove the `(OpenClaw)` heartbeat and cron sections entirely.

7. **BOOT.md** — If platform is NOT openclaw, delete this file (it's an OpenClaw gateway restart hook).

8. **BOOTSTRAP.md** — If platform is NOT openclaw, keep the file but remove OpenClaw-specific language.

---

## Phase 7: OpenClaw Configuration (if platform = openclaw)

Skip this phase entirely if platform is not `openclaw`.

### Essentials (always generated)

Generate the agent entry, model aliases, and basic binding for `openclaw.json`.

See [../../config/reference.md](../../config/reference.md) for complete template details:
- [Agent Entry](../../config/reference.md#agent-entry)
- [Model Aliases](../../config/reference.md#model-aliases)
- [Bindings](../../config/reference.md#bindings)

**Present all essentials as a single config block. Wait for approval before proceeding.**

### Advanced (offered category by category)

Ask: "Want to configure advanced settings? I can walk through each category."

If yes, offer each one:

**1. Tool policy** — Allow/deny lists for tools. See [Tool Policy](../../config/reference.md#tool-policy) for patterns (full access, read-only, safe for groups).

**2. Sandbox** — Docker isolation for non-main sessions. See [Sandbox](../../config/reference.md#sandbox) for modes (off, non-main, all).

**3. Channel bindings** — Route specific channels/DMs/groups to this agent. See [Bindings](../../config/reference.md#bindings) for peer-specific patterns.

**4. Compaction** — Memory flush before context compaction. See [Compaction + Memory Flush](../../config/reference.md#compaction-memory-flush).

**5. Group chat** — Mention patterns, activation mode. See [Group Chat](../../config/reference.md#group-chat).

**6. Block streaming** — Send complete messages instead of streaming. See [Block Streaming](../../config/reference.md#block-streaming).

**Present each advanced section individually. Wait for approval on each.**

Write all OpenClaw config values to `brain.yaml` under the `openclaw` section. The config blocks are for the user to add to their `openclaw.json` — the agent should NOT apply them directly.

---

## Phase 8: Deployment-Specific Setup

### If standalone repo

1. Create `config/` directory if MCP servers were selected (mcporter.json already generated)
2. Initialize git (**only if not already inside a git repo**):
   ```bash
   if ! git rev-parse --is-inside-work-tree 2>/dev/null; then
     git init
   fi
   git checkout -b {agent.branch}
   git add -A
   git commit -m "feat: bootstrap {agent.name} brain from template"
   ```
3. Optionally offer GitHub remote creation:
   ```bash
   gh repo create {github.user}/{github.repo} --private --source=. --remote=origin --push
   ```

### If subfolder mode

1. Files are already placed under `{deployment.subfolder_path}/` in the parent repo
2. The subfolder agent gets **its own** `skills/` and `plugins/` directories — do NOT share the parent's. This keeps agents independent and avoids skill version conflicts.
3. Shared files (`SECURITY.md`, `CONVENTIONS.md`, `PLAYBOOK.md`) stay at the parent root. Remove any copies from the subfolder to avoid duplication.
4. **NEVER run `git init`** — this directory is tracked by the parent repo. Running `git init` here creates a nested repo that breaks parent tracking.
5. Commit to the parent repo's working branch:
   ```bash
   git add {deployment.subfolder_path}/
   git commit -m "feat: add {agent.name} brain as subfolder agent"
   ```

### If OpenClaw platform

1. If hindsight memory selected, document the submodule step:
   ```bash
    git submodule add https://github.com/{github-org}/openclaw-hindsight-retain.git .openclaw/plugins/hindsight-retain
    ```
   Replace `{github-org}` with your organization's GitHub org.
2. Set `agent.skipBootstrap: true` in OpenClaw config to prevent native bootstrap from overwriting
3. Present the full OpenClaw config block for the user to add to their `openclaw.json`

---

## Phase 9: Cleanup

1. Remove `bootstrap/` directory (this skill, substitute.sh, reference.md)
2. If `plugins/` directory is empty: optionally remove it (keep README.md if user wants reference)
3. `brain.yaml` stays as configuration record
4. `META_AGENT_ASSESSMENT.md` — ask if user wants to keep it (only relevant for meta-agent setups)

---

## Phase 10: Multi-Agent (if enabled)

If `multi_agent.enabled` is true:

1. For each additional agent in `multi_agent.agents`:
   - Create `agents/{id}/` directory
   - Copy IDENTITY.md and CONTEXT.md templates
   - Each sub-agent shares root-level SECURITY.md, CONVENTIONS.md, PLAYBOOK.md
2. Update AGENTS.md to reference the multi-agent structure
3. Document routing configuration for OpenClaw

---

## Done!

After bootstrap, the agent's first session should:
1. Read CONTEXT.md, IDENTITY.md, SOUL.md
2. Start building the relationship through conversation
3. Create daily memory files in `memory/`

**Next steps for the human:**
- Review and personalize IDENTITY.md and SOUL.md (the agent drafted content, but you own these files)
- Add org/team knowledge to `knowledge/` if needed
- Configure channel bindings in OpenClaw (if applicable)
- Apply the generated OpenClaw config block to `openclaw.json`
- Start talking to your agent!
