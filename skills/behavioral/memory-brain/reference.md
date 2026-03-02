# Memory & Brain — Reference

Architecture, setup, bootstrapping, and templates for the memory-brain skill. This file is for human operators, not loaded into agent context by default.

---

## Memory Architecture Overview

OpenClaw uses a multi-layered approach to memory, ensuring continuity across sessions and agents.

```
┌──────────────────────────────────────────────────────────────────┐
│                   3-LAYER MEMORY ARCHITECTURE                    │
│                                                                  │
│  LAYER 1: BUILT-IN (memorySearch)                                │
│  • Always-on indexing of memory/ and MEMORY.md                   │
│  • Hybrid BM25 + Vector search                                   │
│                                                                  │
│  LAYER 2: MEMORY SLOT PLUGIN (LanceDB / Hindsight-Retain)        │
│  • Conversation-aware auto-capture and auto-recall               │
│  • Injected directly into agent context                          │
│                                                                  │
│  LAYER 3: HINDSIGHT STANDALONE                                   │
│  • Deep RAG, mental models, and cross-agent sharing              │
│  • Manual retain/recall/reflect for high-signal items            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Combining Backends

Backends are not mutually exclusive. A typical production setup uses **Built-in** for file-based continuity, **LanceDB** for low-latency session memory, and **Hindsight** for long-term organizational knowledge and cross-agent collaboration.

---

## Backend Quick Reference

| Feature | Built-in | LanceDB | Hindsight |
|---------|----------|---------|-----------|
| Config complexity | None | 1 setting | High |
| External dependencies | None | OpenAI API key | Hindsight service |
| Auto-capture | No | Yes | Yes (plugin) |
| Auto-recall | No | Yes | Yes (plugin) |
| Cross-agent sharing | No | No | Yes (commons bank) |
| Retain/recall/reflect | No | No | Yes |
| Local-only option | Yes | No (needs OpenAI) | No |
| File-based truth | Yes | No | Yes (brain files) |

---

## Built-in Memory Search

OpenClaw's native memory backend (SQLite + sqlite-vec) provides zero-config semantic search over your workspace files.

### Configuration

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

### Key Fields
- `enabled`: Activates the background indexing service.
- `sources`: Directories to index (defaults to `memory/`).
- `provider`: Embedding provider (auto-selects local, OpenAI, Gemini, or Voyage).
- `query.hybrid`: Balances keyword (BM25) and semantic (vector) search.

### How it Works
Built-in memory indexes the `memory/` directory and `MEMORY.md` automatically. It also respects `extraPaths` defined in the agent config. It is the "safety net" that ensures agents can always find information stored in their brain files.

---

## LanceDB

A local vector database plugin for fast, session-level memory capture and recall.

### Configuration

```json
{
  "plugins": {
    "slots": { "memory": "memory-lancedb" },
    "entries": {
      "memory-lancedb": {
        "config": {
          "embedding": { "apiKey": "${OPENAI_API_KEY}" },
          "autoCapture": false,
          "autoRecall": true
        }
      }
    }
  }
}
```

### Behavior
- `autoCapture`: Automatically extracts preferences, facts, and decisions from conversations. **Note: Default changed to `false` in v2026.2.14** to reduce noise.
- `autoRecall`: Injects relevant memories into context before each agent turn.
- **Storage**: Local LanceDB files at `~/.openclaw/memory/lancedb`.
- **Requirements**: Requires an `OPENAI_API_KEY` for generating embeddings.

---

## Hindsight (Deep RAG)

Hindsight is the most advanced memory backend, providing structured semantic storage, mental models, and cross-agent knowledge sharing.

### Memory Bank Topology

```
┌────────────────────────────────────────────────────────┐
│                    HINDSIGHT BANKS                      │
│                                                        │
│  Per-Agent Banks (private knowledge)                   │
│  ┌──────────────────────────────────────────────┐      │
│  │  {agent-name}                                │      │
│  │  • Mission, disposition, directives          │      │
│  │  • Agent-specific learnings & task history    │      │
│  │  • Domain expertise & preferences            │      │
│  └──────────────────────────────────────────────┘      │
│                                                        │
│  Shared Bank (cross-agent knowledge)                   │
│  ┌──────────────────────────────────────────────┐      │
│  │  commons                                     │      │
│  │  • User preferences & conventions            │      │
│  │  • Project decisions & architecture           │      │
│  │  • Team information & org knowledge           │      │
│  │  • Shared procedures & standards              │      │
│  └──────────────────────────────────────────────┘      │
│                                                        │
│  Cloned Agents: Same bank ID, different ACLs           │
│  at the gateway level. Clone shares the brain.         │
└────────────────────────────────────────────────────────┘
```

### Bank Rules

| Rule | Description |
|------|-------------|
| **Read** | Agent reads from its own bank AND `commons` |
| **Write** | Agent writes to its own bank only |
| **Promote** | Moving knowledge to `commons` is a manual curation step |
| **Clones** | Share the same bank ID; ACLs handled at the gateway |
| **Orchestrator** | Has its own bank; can read all banks for coordination |

### Brain File Structure

```
{agent-name}/
├── IDENTITY.md              # Who this agent is (human-maintained)
├── SOUL.md                  # Principles, boundaries (human-maintained)
├── CONTEXT.md               # Active working state (agent-maintained)
├── MEMORY.md                # Curated long-term memory (human-reviewed)
├── LEARNINGS.md             # Lessons learned (agent-maintained)
├── TOOLS.md                 # Tool configs, gotchas (agent-maintained)
├── memory/
│   └── YYYY-MM-DD.md        # Daily raw capture (auto-generated)
└── mental-models/
    └── {topic}.md            # Exported from Hindsight mental models
```

### Hindsight Mapping

| Brain File | Hindsight Concept | Sync Direction |
|---|---|---|
| `IDENTITY.md` | Bank profile (mission, disposition) | File → Hindsight |
| `SOUL.md` | Directives | File → Hindsight |
| `CONTEXT.md` | N/A (hot state, changes too fast) | File only |
| `MEMORY.md` | Observations + curated facts | Bidirectional |
| `LEARNINGS.md` | Experience facts | File → Hindsight |
| `TOOLS.md` | World facts (context: `fact`) | File → Hindsight |
| `memory/daily` | Documents (auto-ingested by plugin) | File → Hindsight |
| `mental-models/` | Mental Models | Hindsight → File |

### Naming Rules

**Always use explicit third-person names. Never "User", "user", or "I".**

In multi-agent setups, generic references lose identity. Use "{{agent.name}}" for own actions, "{{owner.name}}" for your human's, and team members by name.

- "User built the plugin" → "{{agent.name}} built the plugin"
- "I learned X the hard way" → "{{agent.name}} learned X the hard way"
- "User prefers time-based batching" → "{{owner.name}} prefers time-based batching"

### Context Taxonomy

| Context | Use For |
|---------|---------|
| `identity` | Who I am (persona, roles) |
| `user:{{owner.name}}` | Facts about {{owner.name}} |
| `team:{name}` | Team member profiles |
| `org:{name}` | Org context (principles, structure) |
| `project:{name}` | Project-specific knowledge |
| `experience` | Things I did/learned |
| `correction` | Mistakes and fixes |
| `preference` | Decisions, likes |
| `fact` | General facts (configs, tools, external info) |

### API Quick Reference

| Operation | Endpoint | When |
|---|---|---|
| Retain | `POST /v1/default/banks/{id}/memories` | Store high-signal items |
| Recall | `POST /v1/default/banks/{id}/memories/recall` | Retrieve relevant context |
| Reflect | `POST /v1/default/banks/{id}/reflect` | Synthesized reasoning (~4k tokens) |
| Consolidate | `POST /v1/default/banks/{id}/consolidate` | Weekly maintenance |
| Create bank | `PUT /v1/default/banks/{id}` | Bootstrap |
| Create directive | `POST /v1/default/banks/{id}/directives` | Sync SOUL.md |
| Create mental model | `POST /v1/default/banks/{id}/mental-models` | Bootstrap |
| Refresh mental model | `POST /v1/default/banks/{id}/mental-models/{mid}/refresh` | Maintenance |
| Bank stats | `GET /v1/default/banks/{id}/stats` | Health checks |
| List tags | `GET /v1/default/banks/{id}/tags` | Cleanup |

### Bootstrapping a New Agent

1. **Create brain files** — Copy templates below, fill in IDENTITY.md and SOUL.md.
2. **Create Hindsight bank:**
   ```
   PUT /v1/default/banks/{agent-name}
   {
     "name": "{Agent Display Name}",
     "mission": "{from IDENTITY.md}",
     "disposition": { "skepticism": 3, "literalism": 3, "empathy": 3 }
   }
   ```
3. **Sync directives** — For each SOUL.md entry:
   ```
   POST /v1/default/banks/{agent-name}/directives
   { "name": "{name}", "content": "{content}", "priority": 5, "is_active": true }
   ```
4. **Ingest brain files** — Retain MEMORY.md, LEARNINGS.md, TOOLS.md as documents with `document_id`.
5. **Create mental models:**
   ```
   POST /v1/default/banks/{agent-name}/mental-models
   {
     "name": "User Preferences",
     "source_query": "What are the user's preferences and coding style?",
     "trigger": { "refresh_after_consolidation": true }
   }
   ```
6. **Create git branch:** `git checkout -b {agent-name}-live && git push -u origin {agent-name}-live`

### Recommended Mental Models

| Model | Source Query |
|---|---|
| User Preferences | "What are {user}'s preferences and coding style?" |
| Project Architecture | "What architectural decisions have been made for {project}?" |
| Active Blockers | "What current blockers or open issues need attention?" |
| Team Norms | "How does the team communicate and make decisions?" |
| Tool Gotchas | "What tool-specific issues and workarounds have been discovered?" |
| Recurring Patterns | "What tasks or requests come up repeatedly?" |

### Maintenance Schedule

- **Weekly Review**: Consolidate daily logs into `MEMORY.md` or `LEARNINGS.md`. Trigger Hindsight `consolidate` endpoint.
- **Monthly Archive**: Move old daily logs to an archive folder.
- **Post-Compaction**: If Hindsight uses compaction, verify critical memories survived.
- **Model Refresh**: Refresh mental models after significant project milestones.

### Bank Disposition Guidelines

| Agent Role | Skepticism | Literalism | Empathy |
|---|---|---|---|
| Code Reviewer | 4-5 | 4 | 2 |
| Personal Assistant | 2 | 2 | 4-5 |
| Issue Triager | 3 | 3 | 3 |
| Doc Generator | 2 | 4 | 2 |
| Orchestrator | 3 | 3 | 3 |

---

## Templates

### IDENTITY.md

```markdown
# {Agent Name}

## Mission
{One paragraph: who this agent is and what it's trying to accomplish}

## Role
{Specific responsibilities and domain}

## Disposition
- Skepticism: {1-5} (1=trusting, 5=skeptical)
- Literalism: {1-5} (1=flexible, 5=literal)
- Empathy: {1-5} (1=detached, 5=empathetic)

## Capabilities
- {List of skills this agent loads}
- {Tools and integrations available}

## Constraints
- {What this agent should NOT do}
- {Boundaries of its authority}
```

### SOUL.md

```markdown
# {Agent Name} — Principles & Boundaries

## Non-Negotiables
1. {Rule that must never be violated}
2. {Rule that must never be violated}

## Principles
1. {Guiding principle for decision-making}
2. {Guiding principle for decision-making}

## Boundaries
- Never {action} without human approval
- Always {action} before {action}

## Communication Style
- {How this agent communicates}
```

### CONTEXT.md

```markdown
# Current Context

## Active Task
{What I'm working on right now}

## Key Context
- {Important active decisions}
- {Current blockers}

## Pending Actions
- [ ] {Action item}

## Open Threads
- {Conversations or questions still in progress}

---
*Last updated: {timestamp}*
```

### MEMORY.md

```markdown
# {Agent Name} — Curated Memory

## Key Decisions
- {Decision + reasoning + date}

## Preferences
- {User/project preferences}

## Procedures
- {Validated procedures that work}

## Patterns
- {Recurring patterns observed}
```

### LEARNINGS.md

```markdown
# {Agent Name} — Learnings

## What Works
- {Approach + why it works + evidence}

## What Doesn't Work
- {Approach + why it failed + what to do instead}

## Lessons
- {Lesson + context + how to apply}
```

---

## Troubleshooting

### General
| Problem | Fix |
|---------|-----|
| Agent forgets mid-conversation | Check plugin status; do explicit retains |
| Brain files out of sync | Re-run sync for changed files |
| New agent has no context | Run full bootstrap |

### Built-in (memorySearch)
| Problem | Fix |
|---------|-----|
| Search returns no results | Ensure `memory/` files exist and are not empty |
| Irrelevant results | Adjust `vectorWeight` vs `textWeight` in config |
| Indexing lag | Restart the agent to force a re-index |

### LanceDB
| Problem | Fix |
|---------|-----|
| Embedding errors | Verify `OPENAI_API_KEY` is valid and has quota |
| Memory noise | Set `autoCapture: false` and use manual retains |
| Storage bloat | Delete `~/.openclaw/memory/lancedb` to reset |

### Hindsight
| Problem | Fix |
|---------|-----|
| Irrelevant recall results | Use context filter; check naming convention |
| Mental models stale | Trigger consolidation; refresh models |
| Identity collapse | Check naming rule — never "User" or "I" |
| Commons too noisy | Tighten promotion criteria |
| API Timeout | Check Hindsight service health and network |
