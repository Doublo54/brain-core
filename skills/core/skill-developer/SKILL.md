---
name: skill-developer
emoji: 🔧
description: "Safely iterate on and improve agent skills. Provides a structured workflow for proposing skill changes that preserves the brain-core → shared-skills → agent sync chain. Use when asked to improve, update, enhance, or fix a skill. Triggers: 'improve this skill', 'update the skill', 'fix the skill', 'enhance the skill', 'the skill should also', 'iterate on the skill'."
version: 1.0.0
metadata:
  openclaw:
    emoji: "🔧"
---

# Skill Developer

Safely iterate on skills without breaking the sync chain: `brain-core → sync-skills.sh → shared-skills → agent symlinks`. Agents **cannot** write to brain-core directly. This workflow bridges the gap using a "break the glass" pattern: break symlink → work on local copy → propose changes → human applies to brain-core → sync restores.

For detailed examples, edge cases, and proposal templates, see [references/development-workflow.md](references/development-workflow.md).

---

## Phase 1 — Start Development

**Command concept:** `develop-skill start <skill-name>`

1. **Identify the skill** — Locate it in your `skills/` directory (verify it's a symlinked skill)
2. **Break the symlink** — Replace the symlink with a real copy of the skill files:
   ```bash
   # Example: banner-studio is a symlink → shared-skills/specialized/banner-studio/
   rm skills/banner-studio/SKILL.md        # remove symlink
   cp -r shared-skills/specialized/banner-studio/* skills/banner-studio/
   ```
3. **Create `_dev_manifest.json`** in the skill directory:
   ```json
   {
     "skill": "banner-studio",
     "started_at": "2026-02-15T14:58:00Z",
     "source": "shared-skills/specialized/banner-studio",
     "developer": "miro",
     "reason": "Add dark theme support",
     "changes": []
   }
   ```
4. Agent now has a **writable local copy**. Sync will skip this skill.

---

## Phase 2 — Develop & Test

- **Modify freely** — Edit SKILL.md, scripts, templates, references, assets
- **Isolation** — Only this agent is affected; other agents use the synced version
- **Track changes** — Append to `_dev_manifest.json.changes` as you work:
  ```json
  {
    "changes": [
      {"file": "scripts/generate.py", "action": "modified", "summary": "Added --dark-theme flag"},
      {"file": "assets/templates/dark-banner.html", "action": "added", "summary": "Dark theme template"}
    ]
  }
  ```
- **Test in context** — Run scripts, verify output, iterate until satisfied

---

## Phase 3 — Propose Changes

**Command concept:** `develop-skill propose <skill-name>`

1. **Generate diff** — Create a unified diff of all changes vs. the original
2. **Create proposal** at `proposals/<skill-name>-<timestamp>.md` with sections:
   - **Summary** — What changed and why
   - **Changes** — File-by-file list with action (added/modified/removed)
   - **Diff** — Unified diff of all changed files
   - **Testing** — What was tested and results
   - **Impact** — Which agents use this skill, backward compatibility notes
3. **Commit proposal** to agent's working branch
4. **Notify human** — The proposal is ready for review in `proposals/`

Human reviews → applies approved changes to brain-core → runs `sync-skills.sh`.

---

## Phase 4 — Finish

**Command concept:** `develop-skill finish <skill-name>`

After human applies changes and runs sync:

1. **Restore symlinks** — Replace local copy with symlinks back to `shared-skills/`
2. **Remove `_dev_manifest.json`** — Skill is no longer in development
3. **Verify** — Confirm the synced version includes the proposed changes
4. **Clean up** — Remove working copies; proposals remain as review trail

---

## Safety Rules

| Rule | Rationale |
|------|-----------|
| **One skill at a time** per agent | Prevents conflicts, simplifies tracking |
| **Never modify `shared-skills/` directly** | It's a deployment cache managed by sync-skills.sh |
| **`_dev_manifest.json` is visible to humans** | Transparency — anyone can see what's in development |
| **`proposals/` directory is git-tracked** | Creates an auditable review trail |
| **Propose, don't deploy** | Changes reach other agents only via brain-core → sync |

---

## sync-skills.sh Integration

When `sync-skills.sh` runs, it should **skip** any skill with a `_dev_manifest.json`:

```bash
# In sync_skill() — before rsync:
if [[ -f "$dst/_dev_manifest.json" ]]; then
    log_warn "Skipping $skill (in development — _dev_manifest.json found)"
    return
fi
```

This prevents sync from overwriting work-in-progress. Once Phase 4 completes (manifest removed, symlinks restored), the next sync runs normally.

---

## Quick Reference

```
┌─────────────────────────────────────────────────┐
│  START     break symlink → copy → manifest      │
│  DEVELOP   modify local copy → track changes    │
│  PROPOSE   diff → proposal file → commit        │
│  FINISH    human applies → sync → restore links  │
└─────────────────────────────────────────────────┘
```

**Abort without proposing:** Restore symlinks + delete `_dev_manifest.json`. No changes propagate.
