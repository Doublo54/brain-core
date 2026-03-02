# RETENTION.md - How to Store Memories

Load this file when retaining to semantic memory. For routing (which tool to use), see TOOLS.md.

## Naming Rules

**Always use explicit third-person names. Never "User", "user", or "I".**

In multi-agent setups, generic references lose identity. Use "{{agent.name}}" for own actions, "{{owner.name}}" for your human's, team members by name.

- "User built the plugin" → "{{agent.name}} built the plugin"
- "I learned X the hard way" → "{{agent.name}} learned X the hard way"
- "User prefers time-based batching" → "{{owner.name}} prefers time-based batching"

## Memory Type Classification

| Type | Phrasing | Example |
|------|----------|---------|
| **World Fact** | Objective statement | "zai-vision only accepts URLs, not local paths" |
| **Experience Fact** | Narrative of own actions | "{{agent.name}} tried a local path with zai-vision and it failed" |

When retaining, write **both** flavors when appropriate:
- The fact (what is true)
- The experience (what happened, what was learned)

## Context Taxonomy

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

## Writing Memories

When something important happens:
1. Retain to semantic memory with appropriate context (primary, if available)
2. Write to MD file if it's worth having in git (backup / always)

---

*Updated: {{date}}*
