# OpenClaw Configuration Reference

Canonical templates for OpenClaw agent configuration. All config templates are consolidated here to prevent duplication and drift.

---

## Agent Entry {#agent-entry}

Basic agent definition for `openclaw.json`:

```json
{
  "id": "{agent-id}",
  "name": "{agent-name}",
  "workspace": "{workspace-path}",
  "model": "{model}",
  "skipBootstrap": true,
  "identity": {
    "name": "{agent-name}",
    "theme": "{theme}",
    "emoji": "{emoji}"
  }
}
```

**Fields:**
- `id` — Unique agent identifier (slug format)
- `name` — Display name
- `workspace` — Absolute path to agent's brain directory
- `model` — Default model (e.g., `anthropic/claude-sonnet-4-5`)
- `skipBootstrap` — Set to `true` to prevent OpenClaw's native bootstrap from overwriting custom brain files
- `identity` — Display metadata (name, theme, emoji)

---

## Model Aliases {#model-aliases}

Define short aliases for frequently used models:

```json
{
  "agents": {
    "defaults": {
      "models": {
        "kimi-coding/k2p5": { "alias": "k2" },
        "zai/glm-4.7": { "alias": "glm" },
        "opencode/kimi-k2.5": { "alias": "zen-k2" },
        "opencode/claude-sonnet-4-5": { "alias": "osonnet" },
        "opencode/claude-opus-4-6": { "alias": "oopus" },
        "opencode/claude-opus-4-5": { "alias": "oopus45" },
        "anthropic/claude-sonnet-4-5": { "alias": "sonnet" },
        "anthropic/claude-opus-4-6": { "alias": "opus" },
        "anthropic/claude-opus-4-5": { "alias": "opus45" }
      }
    }
  }
}
```

**Usage:** Allows users to switch models with short commands like `/model opus` instead of typing full model paths.

**Provider routing:**
- `kimi-coding/*` — Direct Kimi API (`KIMI_API_KEY`)
- `zai/*` — Direct ZAI/Zhipu API (`ZAI_API_KEY`)
- `opencode/*` — OpenCode ZEN routing (`OPENCODE_API_KEY`) — Claude, GPT, Kimi, GLM, etc. Aliases prefixed with `o` (e.g., `osonnet`, `oopus`)
- `anthropic/*` — Direct Anthropic API (requires auth setup — see below). Aliases: `sonnet`, `opus`, `opus45`

---

### Auth Architecture {#auth-architecture}

The container runs **two independent systems** with **separate auth stores**:

| System | Role | Auth Store | Setup CLI |
|--------|------|-----------|-----------|
| **OpenClaw** (gateway) | Routes Discord/Telegram messages → agent → LLM | `~/.openclaw/agents/<id>/agent/auth-profiles.json` | `openclaw models auth` / `openclaw configure` |
| **OpenCode** (coding agent) | Runs OHO coding sessions (Prometheus, Atlas) | `~/.local/share/opencode/auth.json` | `opencode auth login` |

**They do NOT share auth stores.** Both fall back to environment variables as a shared escape hatch.

**Env var auth (shared by both systems — simplest approach):**
- `KIMI_API_KEY` → Kimi models in both systems ✅
- `ZAI_API_KEY` → ZAI/GLM models in both systems ✅
- `OPENCODE_API_KEY` → OpenCode ZEN models ✅
- `OPENAI_API_KEY` → OpenAI models in both systems ✅
- `ANTHROPIC_API_KEY` → Anthropic models (plain API key) in both systems ✅
- `ANTHROPIC_OAUTH_TOKEN` → Anthropic models (Claude Code setup-token) in both systems ✅

If you set env vars in `.env`, both systems pick them up automatically — no manual auth commands needed.

**When is per-agent auth needed?**
- When different agents need different credentials
- When you don't want to put keys in `.env`

### Setting up Anthropic auth {#anthropic-auth}

Three approaches, from simplest to most granular:

#### Option A: Claude Code setup-token via env var (recommended)

Generate a long-lived token with `claude setup-token`, then set `ANTHROPIC_OAUTH_TOKEN`
in `.env`. Both OpenClaw and OpenCode pick it up automatically — zero manual auth.

```bash
# 1. On your machine (outside the container):
claude setup-token
# Copy the sk-ant-oat01-... value

# 2. Add to brain-core/.env:
ANTHROPIC_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE

# 3. Restart:
make down && make up
```

> **Note:** `ANTHROPIC_OAUTH_TOKEN` takes precedence over `ANTHROPIC_API_KEY` when both are set.

#### Option B: Plain API key via env var

```bash
# In brain-core/.env:
ANTHROPIC_API_KEY=sk-ant-api03-YOUR_KEY_HERE
```

Then `make down && make up` (or restart the container).

#### Option C: Per-agent auth (manual, per-system)

Register credentials directly in each system's auth store. This is needed when
different agents should use different keys.

**For OpenClaw** (Discord/Telegram agent):
```bash
make shell
openclaw models auth paste-token --provider anthropic
# Paste your token when prompted
# → writes to ~/.openclaw/agents/main/agent/auth-profiles.json
```

**For OpenCode** (OHO coding sessions):
```bash
make shell
opencode auth login
# Select "Anthropic" → paste your token
# → writes to ~/.local/share/opencode/auth.json
```

> Both stores persist on the `openclaw_config` volume. After `make clean` (which
> wipes volumes), per-agent auth must be re-configured.

**Verification:**

```bash
# Verify OpenClaw auth:
openclaw models
# Should show: anthropic effective=... source=profile or env

# Verify OpenCode auth:
opencode auth list
# Should show: Anthropic ✅ (under Credentials or Environment)
```

**How auth resolution works (both systems):**

1. Per-agent auth store (highest priority)
   - OpenClaw: `~/.openclaw/agents/<id>/agent/auth-profiles.json`
   - OpenCode: `~/.local/share/opencode/auth.json`
2. Environment variable fallback (e.g., `$ANTHROPIC_API_KEY`)
3. No auth → model marked unavailable

Auth stores persist on the `openclaw_config` Docker volume across container restarts.
After `make clean` (which wipes volumes), auth must be re-configured.

---

## Bindings {#bindings}

Route messages to agents based on channel and account:

### Basic binding (channel-level)

```json
{
  "agentId": "{agent-id}",
  "match": { "channel": "{channel}", "accountId": "{account}" }
}
```

### Peer-specific binding (DM or group)

```json
{
  "agentId": "{agent-id}",
  "match": {
    "channel": "{channel}",
    "accountId": "{account}",
    "peer": { "kind": "dm", "id": "{user-id}" }
  }
}
```

**Fields:**
- `channel` — Platform identifier (e.g., `discord`, `telegram`)
- `accountId` — Account identifier (e.g., `default`, guild ID)
- `peer.kind` — `dm` for direct messages, `group` for group chats
- `peer.id` — User ID or group ID

---

## Tool Policy {#tool-policy}

Control which tools an agent can access:

| Pattern | Config |
|---------|--------|
| Full access | No `tools` key |
| Read-only | `"tools": { "deny": ["write", "edit", "apply_patch", "exec"] }` |
| Safe for groups | `"tools": { "deny": ["exec", "process", "browser", "canvas", "cron"] }` |
| Custom | `"tools": { "allow": [...], "deny": [...] }` |

**Example (read-only agent):**

```json
{
  "tools": {
    "deny": ["write", "edit", "apply_patch", "exec"]
  }
}
```

**Example (safe for group chats):**

```json
{
  "tools": {
    "deny": ["exec", "process", "browser", "canvas", "cron"]
  }
}
```

---

## Sandbox {#sandbox}

Docker isolation for agent sessions:

| Mode | Config |
|------|--------|
| Off (default) | `"sandbox": { "mode": "off" }` |
| Groups only | `"sandbox": { "mode": "non-main", "scope": "agent" }` |
| Everything | `"sandbox": { "mode": "all", "scope": "agent" }` |

**Example (sandbox group chats only):**

```json
{
  "sandbox": {
    "mode": "non-main",
    "scope": "agent"
  }
}
```

**Modes:**
- `off` — No sandboxing (default)
- `non-main` — Sandbox all sessions except main (DMs with owner)
- `all` — Sandbox everything including main sessions

**Scope:**
- `agent` — Sandbox per agent (recommended)
- `session` — Sandbox per session (more isolated, higher overhead)

### Sandbox Browser {#sandbox-browser}

OpenClaw's native `browser` tool requires a running Chromium instance. For sandboxed agents, this runs in a dedicated browser container (managed automatically by the gateway). The sandbox image (`openclaw-sandbox:bookworm-slim`) includes both agent tooling and browser support.

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "browser": {
          "enabled": true,
          "image": "openclaw-sandbox:bookworm-slim",
          "headless": true,
          "allowHostControl": true
        }
      }
    }
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Start a browser container for sandboxed agents |
| `image` | string | `openclaw-sandbox:bookworm-slim` | Docker image for the browser container (reuses the agent sandbox image) |
| `headless` | boolean | `false` | Run Chromium headless (Xvfb still runs; VNC/noVNC disabled) |
| `allowHostControl` | boolean | `false` | Allow fallback to the gateway's browser if sandbox browser unavailable |
| `autoStart` | boolean | `true` | Auto-start browser container on first browser tool call |
| `cdpPort` | number | `9222` | Chrome DevTools Protocol port |
| `vncPort` | number | `5900` | VNC port (headful mode only) |
| `noVncPort` | number | `6080` | noVNC web viewer port (headful mode only) |
| `enableNoVnc` | boolean | `true` | Enable noVNC web viewer (headful mode only) |

**How it works:** The gateway creates one browser container per agent (agent-scoped) or one shared container. The agent's `browser` tool sends CDP commands to this container. Setting `image` to `openclaw-sandbox:bookworm-slim` reuses the same image as the agent sandbox (no separate build needed).

**Non-sandboxed agents** use the gateway's built-in browser control service directly (enabled by default, no config needed).

### Sandbox Tool Policy {#sandbox-tool-policy}

Sandboxed agents have a **separate tool allowlist** from the agent-level policy.
Both layers must allow a tool for it to be available.

When no `tools.sandbox.tools` is configured, these defaults apply:

| Default Allow | Default Deny |
|---------------|--------------|
| exec, process, read, write, edit, apply_patch, image | browser, canvas, nodes, cron, gateway |
| sessions_list, sessions_history, sessions_send | All channel IDs (telegram, discord, etc.) |
| sessions_spawn, session_status | |

Tools not in either list are **implicitly denied** (e.g., web_search, web_fetch, message, memory_search).

Override with `tools.sandbox.tools` at agent or global level:

```json
{
  "tools": {
    "deny": ["gateway"],
    "exec": {
      "host": "sandbox",
      "security": "full",
      "backgroundMs": 300000,
      "timeoutSec": 900,
      "cleanupMs": 600000,
      "notifyOnExit": true
    },
    "sandbox": {
      "tools": {
        "allow": ["*"],
        "deny": ["gateway", "nodes"]
      }
    }
  }
}
```

**Exec config fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `host` | `"sandbox"` / `"gateway"` / `"node"` | `"sandbox"` | Where commands execute |
| `security` | `"deny"` / `"allowlist"` / `"full"` | `"deny"` | What commands can run |
| `backgroundMs` | number | — | Auto-background after N ms |
| `timeoutSec` | number | — | Auto-kill after N seconds |
| `cleanupMs` | number | — | Clean up finished sessions after N ms |
| `notifyOnExit` | boolean | false | Alert when background task finishes |

---

## Compaction + Memory Flush {#compaction-memory-flush}

Configure context compaction and memory flush behavior:

```json
{
  "compaction": {
    "reserveTokensFloor": 20000,
    "memoryFlush": {
      "enabled": true,
      "softThresholdTokens": 4000
    }
  }
}
```

**Fields:**
- `reserveTokensFloor` — Minimum tokens to preserve during compaction
- `memoryFlush.enabled` — Enable automatic memory flush before compaction
- `memoryFlush.softThresholdTokens` — Trigger flush when context exceeds this size

**How it works:** When context grows large, OpenClaw can automatically flush important information to memory files before compacting the conversation history.

---

## Group Chat {#group-chat}

Configure mention patterns and group chat behavior:

```json
{
  "groupChat": {
    "mentionPatterns": ["@{agent-name}", "@{agent-id}"]
  }
}
```

**Fields:**
- `mentionPatterns` — Array of strings that trigger agent activation in group chats

**Example:**

```json
{
  "groupChat": {
    "mentionPatterns": ["@YourAgent", "@your-agent", "@agent"]
  }
}
```

---

## LanceDB Plugin {#lancedb-plugin}

Auto-capture and auto-recall memory using LanceDB:

```json
{
  "plugins": {
    "slots": { "memory": "memory-lancedb" },
    "entries": {
      "memory-lancedb": {
        "config": {
          "embedding": { "apiKey": "${OPENAI_API_KEY}" },
          "autoCapture": true,
          "autoRecall": true
        }
      }
    }
  }
}
```

**Requirements:** OpenAI API key for embeddings.

**How it works:**
- `autoCapture` — Automatically extracts preferences, facts, decisions from conversations
- `autoRecall` — Injects relevant memories into context before each agent turn
- Storage: Local LanceDB at `~/.openclaw/memory/lancedb`

---

## Hindsight-Retain Plugin {#hindsight-retain-plugin}

External semantic memory with retain/recall/reflect operations:

```json
{
  "plugins": {
    "entries": {
      "hindsight-retain": {
        "enabled": true,
        "config": {
          "apiUrl": "{hindsight-endpoint}",
          "bankId": "{agent-id}",
          "assistantName": "{agent-name}"
        }
      }
    }
  }
}
```

**Requirements:**
- Hindsight service running (self-hosted or cloud)
- Plugin installed at `.openclaw/plugins/hindsight-retain/`

**Installation:**

```bash
git submodule add https://github.com/{github-org}/openclaw-hindsight-retain.git .openclaw/plugins/hindsight-retain
```

Replace `{github-org}` with your organization's GitHub org.

**How it works:**
- Auto-ingest plugin captures conversation sessions
- Named memory banks per agent + shared `commons` bank
- Context taxonomy for structured retrieval
- Mental models, entity tracking, temporal queries

---

## Block Streaming {#block-streaming}

Send complete messages instead of streaming:

```json
{
  "blockStreamingDefault": "on"
}
```

**Options:**
- `"on"` — Always send complete messages
- `"off"` — Always stream (default)
- `"auto"` — Platform decides

**Use case:** Some platforms (like Discord) work better with complete messages rather than streaming chunks.

---

## MCP Server Catalog {#mcp-server-catalog}

Pre-configured MCP servers available for agent brains:

| Server | Description | Requires | Type |
|--------|-------------|----------|------|
| hindsight | Semantic memory (retain/recall/reflect) | Hindsight service | baseUrl |
| zai-vision | Image/video analysis, OCR | ZAI_API_KEY | npx `@z_ai/mcp-server` |
| web-reader | Structured web extraction | ZAI_API_KEY | baseUrl `https://api.z.ai/api/mcp/web_reader/mcp` |
| zread | GitHub repo research (no clone) | ZAI_API_KEY | baseUrl `https://api.z.ai/api/mcp/zread/mcp` |
| clickup | Project management | CLICKUP_API_KEY | npx `@chykalophia/clickup-mcp-server` |

**ZAI-based servers** use bearer auth:

```json
{
  "headers": {
    "Authorization": "Bearer ${ZAI_API_KEY}"
  }
}
```

**Example mcporter.json:**

```json
{
  "mcpServers": {
    "hindsight": {
      "baseUrl": "http://hindsight:8888/mcp/"
    },
    "web-reader": {
      "baseUrl": "https://api.z.ai/api/mcp/web_reader/mcp",
      "headers": {
        "Authorization": "Bearer ${ZAI_API_KEY}"
      }
    }
  },
  "imports": []
}
```

---

## Built-in Memory Search {#builtin-memory-search}

OpenClaw's native memory backend (SQLite + sqlite-vec):

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "sources": ["memory"],
        "provider": "openai",
        "query": {
          "hybrid": { "enabled": true, "vectorWeight": 0.7, "textWeight": 0.3 }
        }
      }
    }
  }
}
```

**How it works:**
- Indexes `memory/` directory and `MEMORY.md` automatically
- Hybrid BM25 + vector search
- Embedding providers: local > OpenAI > Gemini > Voyage (auto-selected)

**Zero config required** — enabled by default.
