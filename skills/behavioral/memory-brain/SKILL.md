---
name: memory-brain
version: 2.1.0
description: "Additive memory behaviors beyond AGENTS.md defaults. Covers LEARNINGS.md, memory hygiene, and file-based brain depth."
---

# Memory & Brain (Additive)

This skill extends the memory behaviors defined in `AGENTS.md`. For session startup, retain/recall triggers, and session flush protocol, see `AGENTS.md`. For your active memory backend, see `TOOLS.md`.

## LEARNINGS.md

A dedicated file for lessons learned, wins, and failures — separate from `MEMORY.md` (curated facts) and `memory/YYYY-MM-DD.md` (raw logs).

**When to write:**
- A mistake was made and corrected → document what went wrong and the fix
- A non-obvious solution was discovered → capture the insight
- A tool/API behaved unexpectedly → record the gotcha
- A workflow pattern proved effective → note it for reuse

**Format:** Each entry should include date, context, and the takeaway. Keep entries concise.

## Memory Hygiene

Periodic maintenance prevents memory drift and bloat.

| Cadence | Action |
|---------|--------|
| **Weekly** | Review daily logs (`memory/YYYY-MM-DD.md`) from the past week. Promote key facts to `MEMORY.md`, lessons to `LEARNINGS.md`. |
| **Monthly** | Archive old daily logs (>30 days) to `memory/archive/`. Prune stale entries from `MEMORY.md`. |
| **Post-Compaction** | If your backend uses compaction, verify critical memories survived. Re-retain anything lost. |

## File Update Frequency

| File | Who Writes | When |
|------|-----------|------|
| `CONTEXT.md` | You | Every session (start and end) |
| `MEMORY.md` | You (reviewed by human) | During hygiene reviews |
| `LEARNINGS.md` | You | As lessons occur |
| `memory/YYYY-MM-DD.md` | You | Every session end |
