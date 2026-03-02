# Memory Backend Options

This template supports four memory tiers. Choose based on your needs and infrastructure.

---

## Tier 1: Built-in memorySearch (default)

**Zero config. Always available.**

OpenClaw's native memory uses SQLite + sqlite-vec with hybrid BM25+vector search. It indexes your `memory/` directory and `MEMORY.md` automatically.

**Setup:** Nothing — it's enabled by default via `memorySearch.enabled: true`.

**How it works:**
- Write to `memory/YYYY-MM-DD.md` and `MEMORY.md` — files are auto-indexed
- Agent uses `memory_search` tool to find relevant notes
- Embedding providers auto-selected: local > OpenAI > Gemini > Voyage

**Config options:**
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

**Best for:** Getting started, simple setups, when you want full control over what's stored.

---

## Tier 2: LanceDB (bundled plugin)

**One config line. Auto-capture + auto-recall.**

OpenClaw's bundled LanceDB plugin automatically captures important information from conversations and injects relevant memories before each turn.

**Setup:**
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

**Requires:** OpenAI API key (for embeddings).

**How it works:**
- Auto-capture extracts preferences, facts, decisions, entities from every conversation
- Auto-recall injects relevant memories into context before each agent turn
- Storage: local LanceDB at `~/.openclaw/memory/lancedb`
- Embedding models: `text-embedding-3-small` (default) or `text-embedding-3-large`

**Best for:** "Set and forget" memory that improves automatically over time.

---

## Tier 3: QMD (experimental)

**Enhanced local search with reranking.**

QMD is a local-first search sidecar that combines BM25 + vectors + reranking.

**Setup:**
```json
{
  "memory": {
    "backend": "qmd",
    "qmd": {
      "includeDefaultMemory": true,
      "update": { "interval": "5m" }
    }
  }
}
```

**Requires:** QMD CLI installed (`bun install -g github.com/tobi/qmd`).

**How it works:**
- Indexes markdown files + optionally session transcripts
- Runs fully locally via Bun + node-llama-cpp (no external API needed)
- Falls back to built-in SQLite if QMD binary is missing

**Best for:** Privacy-first setups, when you want enhanced search without external APIs.

---

## Tier 4: Hindsight (external RAG)

**Full semantic memory with named banks and cross-agent sharing.**

Hindsight is an external RAG service that provides retain/recall/reflect operations with context taxonomy and named memory banks.

**Setup:**
1. Deploy Hindsight service (self-hosted or cloud)
2. Add MCP server config to `config/mcporter.json` (generated during bootstrap)
3. Install the `hindsight-retain` plugin into your workspace:

**Installing the plugin (git submodule — recommended):**
```bash
# From your brain repo root:
git submodule add https://github.com/{github-org}/openclaw-hindsight-retain.git .openclaw/plugins/hindsight-retain
```

Replace `{github-org}` with your organization's GitHub org.

Or clone manually:
```bash
git clone https://github.com/{github-org}/openclaw-hindsight-retain.git .openclaw/plugins/hindsight-retain
```

The plugin lives at `.openclaw/plugins/hindsight-retain/` in your workspace. OpenClaw auto-discovers workspace plugins.

**Plugin config (openclaw.json):**
```json
{
  "plugins": {
    "entries": {
      "hindsight-retain": {
        "enabled": true,
        "config": {
          "apiUrl": "http://hindsight:8888",
          "bankId": "{agent-id}",
          "assistantName": "{agent-name}"
        }
      }
    }
  }
}
```

**How it works:**
- Retain/recall/reflect operations via MCP (mcporter)
- Named memory banks per agent + shared `commons` bank
- Auto-ingest plugin captures conversation sessions
- Context taxonomy for structured retrieval
- Mental models, entity tracking, temporal queries

**Best for:** Multi-agent setups, when you need cross-agent knowledge sharing, or when you want the most powerful memory system.

---

## Comparison

| Feature | Built-in | LanceDB | QMD | Hindsight |
|---------|----------|---------|-----|-----------|
| Config complexity | None | 1 setting | Moderate | High |
| External dependencies | None | OpenAI API key | QMD CLI | Hindsight service |
| Auto-capture | No | Yes | No | Yes (plugin) |
| Auto-recall | No | Yes | No | Yes (plugin) |
| Cross-agent sharing | No | No | No | Yes (commons bank) |
| Retain/recall/reflect | No | No | No | Yes |
| Local-only option | Yes | No (needs OpenAI) | Yes | No |
| File-based truth | Yes | No | Yes | Yes (brain files) |

---

## Combining Backends

You can use multiple tiers together:
- **Built-in + Hindsight**: memorySearch for file-based notes, Hindsight for semantic memory
- **LanceDB + file-based**: LanceDB for auto-capture, still write important things to files for git backup
- The `memory-brain` skill in `skills/` is designed to work with any combination

---

## MCP Server Catalog

These MCP servers can be configured during bootstrap. The bootstrap starts with **zero MCPs** and lets you pick which to enable.

See [../../config/reference.md#mcp-server-catalog](../../config/reference.md#mcp-server-catalog) for the complete catalog with setup instructions, authentication details, and example `mcporter.json` configuration.
