# TOOLS.md - Local Notes

Skills define *how* tools work. This file is for *your* specifics.

## Memory Backend

**Active backend:** {{memory.backend}}

<!-- BEGIN:backend=builtin -->
### Built-in Memory (memorySearch)

**Active tool:** `memory_search` (hybrid BM25 + vector search)

This backend indexes your file-based brain automatically. It provides a bridge between your raw markdown notes and semantic retrieval.

- **What gets indexed:** The `memory/` directory, `MEMORY.md`, and any `extraPaths` defined in your config.
- **How to use:** Simply write your notes to `memory/YYYY-MM-DD.md` or curate long-term facts in `MEMORY.md`. The system auto-indexes these files on change.
- **Search triggers:** Use `memory_search` when you need to find specific past decisions, project details, or context that isn't in your immediate window.
- **No explicit retention:** Since it's file-based, "retaining" means writing to a file. There are no separate `retain` or `recall` tool calls needed beyond standard file operations and `memory_search`.
- **Hybrid Search:** Combines keyword matching (BM25) with semantic vector search for high accuracy.
<!-- END:backend=builtin -->

<!-- BEGIN:backend=lancedb -->
### LanceDB (Auto-Memory)

**Active plugin:** `memory-lancedb`

LanceDB provides a "set and forget" semantic memory that operates automatically in the background.

- **Auto-Capture:** The system automatically extracts preferences, facts, decisions, and entities from every conversation turn. It watches for high-signal statements and stores them without explicit tool calls.
- **Auto-Recall:** Relevant memories are automatically injected into your context before each turn, providing seamless continuity across sessions.
- **Manual Search:** The `memory_search` tool remains available for explicit lookups against your file-based brain (`memory/` and `MEMORY.md`).
- **Requirements:** Requires a valid `OPENAI_API_KEY` for generating embeddings. It uses `text-embedding-3-small` by default for efficient, high-quality vectors.
- **Storage:** Data is stored locally in a LanceDB instance at `~/.openclaw/memory/lancedb`. This ensures your semantic memory stays on your machine.
- **Configuration:** Note that `autoCapture` must be explicitly set to `true` in your config (it defaults to `false` as of v2026.2.14).
- **Best Practice:** Even with auto-capture, continue writing critical milestones and curated knowledge to `MEMORY.md`. This provides a human-readable, git-backed source of truth that complements the semantic store.
- **Triggers:** While capture is automatic, you can influence it by being explicit: "Remember that {{owner.name}} prefers the dark theme."
- **Hybrid Approach:** Use LanceDB for broad semantic recall and file-based memory for precise, version-controlled documentation.
- **Maintenance:** The system handles compaction and indexing automatically, so no manual maintenance is required.
<!-- END:backend=lancedb -->

<!-- BEGIN:backend=hindsight -->
### Hindsight (Semantic RAG)

**Active bank:** `{{memory.bank_id}}`
**MCP Server:** `hindsight` (configured in `mcporter.json`)

Hindsight is your high-fidelity semantic memory. It uses a structured taxonomy to store and retrieve knowledge across sessions.

#### Available Tools
- `hindsight.retain(context, document_tags)`: Store new information with specific metadata.
- `hindsight.recall(query, context)`: Retrieve relevant memories using semantic search.
- `hindsight.reflect(question)`: LLM-powered reasoning over your memory bank for complex synthesis.
- `memory_search`: Still available for searching local markdown files.

#### Retention Protocol (WAL - Write-Ahead Logging)
**Always retain BEFORE responding.** If you learn something vital or a decision is made, call `retain` immediately. This ensures the memory is captured even if the session crashes or the response is interrupted. Treat memory as a write-ahead log for your consciousness.

#### Naming rules (third-person)
Always use explicit third-person names. Never use generic terms like "User" or "I".
- Use `{{agent.name}}` for your own actions and learnings.
- Use `{{owner.name}}` for your human's preferences and instructions.
- Example: `{{agent.name}} learned that the build fails without the legacy flag.`

#### Context taxonomy
Use these categories to keep your memory organized and searchable:
- `identity`: Your persona, roles, and core instructions.
- `user:{{owner.name}}`: Facts and preferences specific to your human.
- `team:{name}` / `org:{name}`: Organizational structure and team context.
- `project:{name}`: Knowledge specific to a particular project or repository.
- `experience`: Narrative accounts of things you did or lessons you learned.
- `correction`: Mistakes you made and the corrections you received.
- `preference` / `fact`: General decisions, settings, or objective truths.

#### Dual-Flavor Retention
When appropriate, store both the **Fact** (objective truth) and the **Experience** (narrative account).
- **Fact:** "The API requires a Bearer token."
- **Experience:** "{{agent.name}} tried a Basic token and received a 401 error."

#### Commons bank
Shared knowledge that should be accessible to other agents should be tagged with `promote:pending`. This allows it to be reviewed and moved to the `commons` bank for cross-agent awareness.
<!-- END:backend=hindsight -->

## MCP Servers

<!-- The bootstrap populates this from your MCP selections.
     If bootstrapping manually, list your configured servers here. -->

## GitHub

- **User:** {{github.user}} (ID: {{github.user_id}})
- **Brain repo:** `{{github.user}}/{{github.repo}}` (private)

## Context-Heavy Tools (USE SPARINGLY)

| Tool | Typical Size | Notes |
|------|--------------|-------|
| `sessions_list` with `messageLimit` | 100-150k tokens | Returns full message histories |
| `Read` on large files | varies | Check file size first |

---

*Updated: {{date}}*
