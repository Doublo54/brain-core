# CONVENTIONS.md — Workspace Standards

*Reference doc for file lifecycle, naming, and hygiene rules.*
*Not loaded every session — consult when needed.*

---

## File Lifecycle

### Memory Files
- **Daily logs** (`memory/YYYY-MM-DD.md`) — raw notes of what happened
- **Long-term** (`MEMORY.md`) — curated, distilled from daily logs

### Skills
- Keep if actively used
- Delete stubs/placeholders that won't be implemented
- Update TOOLS.md when adding/removing skills

---

## Edit Discipline

**Before editing any file:**
1. Read the WHOLE file (or relevant section) first
2. Search for existing content before adding new
3. Check for duplicate headers

**After major edits:**
1. Quick scan for accidental duplicates
2. Verify refs still work
3. Update "Last updated" timestamp if present

---

## Cron Hygiene

### One-Time Crons
- Mark clearly with date or `[ONE-TIME]` in name
- After firing: disable or delete within 24h

### Regular Crons
- Review periodically: still needed?
- Document purpose in cron text

---

## Naming Conventions

### Files
- Daily memory: `memory/YYYY-MM-DD.md`
- Archives: `memory/archive/[original-name].md`

### Config
- Use `${VAR_NAME}` for secrets in templates
- Never commit real credentials

---

*Consult when unsure. Keep it clean.*
