---
name: upgrade-agent
version: 1.0.0
description: "Upgrade existing agent brains when the brain-core template is updated. Diffs template changes, selectively applies safe updates, preserves personalized files. Use when the template has been updated or when asked to upgrade an agent's brain structure."
---

# Upgrade Agent

Apply brain-core template updates to existing agents without overwriting personalized content.

---

## File Classification

Files are classified by how they should be handled during upgrades:

**Auto-update files (safe)** (framework files — not personalized):
- `CONVENTIONS.md`, `PLAYBOOK.md`, `HEARTBEAT.md`
- `skills/behavioral/memory-brain/SKILL.md`, `skills/behavioral/memory-brain/reference.md`
- `skills/behavioral/proactive-agent-behavior/SKILL.md`, `skills/behavioral/proactive-agent-behavior/reference.md`
- *Note: These update automatically during minor version upgrades.*

**Merge-required files (admin review)** (may have agent-specific additions):
- `AGENTS.md` — diff and merge, preserve custom rules
- `SECURITY.md` — preserve admin IDs, merge structural changes
- `RETENTION.md` — preserve custom context taxonomy entries
- `.gitignore` — append new patterns, don't remove existing
- *Note: These require admin approval for changes.*

**Never-touch files (identity)** (personalized by the agent/human):
- `IDENTITY.md`, `SOUL.md`, `USER.md`
- `CONTEXT.md`, `MEMORY.md`
- `TOOLS.md` (has agent-specific backend config and MCP list)
- `brain.yaml` (except for `template_version` field)
- `memory/` (all daily logs)
- `knowledge/` (all knowledge files)
- `config/mcporter.json`
- *Note: These are NEVER modified by any upgrade; they contain the agent's personality and memory.*

---

## Template Version Tracking

### Version Comparison
1. **Check Current Version:** Read the agent's `template_version` from its `brain.yaml`.
2. **Check Latest Version:** Read the latest `template_version` from `brain-core/template/brain.yaml`.
3. **Logic:** If `agent_version < template_version`, an upgrade is needed.

### Version Types
- **Major version (e.g., 1.0 → 2.0):** Structural changes, breaking updates, or schema migrations. Requires careful manual review and potentially data transformation.
- **Minor version (e.g., 1.0 → 1.1):** Safe content updates, bug fixes in framework files. Can auto-apply "Safe" files.

### Cross-schema Upgrades
If a major version changes the `brain.yaml` schema itself (e.g., flat → nested):
- Read the old format.
- Transform values to the new format.
- Write the new format while preserving all custom values (e.g., agent name, owner info).
- Ensure `template_version` is updated to the new version.

---

## Workflow

### 1. Identify Target

Which agent to upgrade? Read `knowledge/agents/registry.md` for the list of active agents and their template versions.

### 2. Fetch Latest Template

Use the template from the local `brain-core/template/` directory. This is the canonical source.

If brain-core is not available locally, fall back to cloning it:
```
git clone <brain-core-repo-url> /tmp/brain-core
# Template is at /tmp/brain-core/template/
```

### 3. Diff

Compare the agent's current files against the latest template. Focus on "safe to overwrite" and "merge carefully" files only. Ignore "never overwrite" files.

Present the diff summary:
- Files with changes (show what changed)
- New files added to the template
- Files removed from the template

### 4. Apply

**Safe files:** Overwrite directly from the template.

**Merge files:** Show the diff for each file. Ask the human whether to:
- Accept the template version
- Keep the current version
- Manually merge (show both versions)

**New files:** Copy from template. If they contain `{{var}}` placeholders, substitute from the agent's `brain.yaml`.

### 5. Skills Update

Skills are safe to overwrite since they're framework files. But if the agent added custom skills (not from the template), preserve those.

Check: does the agent have skills that don't exist in the template? If yes, keep them.

### 6. Update Registry

Update the template version in `knowledge/agents/registry.md` for this agent.

### 7. Commit

Commit the changes to the agent's working branch with a descriptive message noting which template version was applied.

---

## Batch Upgrade

### "Upgrade All Agents" Flow
1. **Registry Scan:** Read `knowledge/agents/registry.md` to identify all active agents.
2. **Version Check:** For each agent, compare its `template_version` (from its `brain.yaml`) against the latest version in `brain-core`.
3. **Report Generation:** Generate an upgrade report summarizing:
   - Which agents need upgrading.
   - The version jump (e.g., 1.0 → 1.1).
   - List of files that will be auto-updated vs. those requiring merge review.
4. **Approval:** Present the report to the admin for approval.
5. **Sequential Execution:** On approval, execute upgrades one by one (not in parallel) to ensure stability.
6. **Finalize:**
   - Update each agent's `template_version` in its `brain.yaml`.
   - Update `knowledge/agents/registry.md` with the new version numbers.

### Rollback Guidance
If an upgrade fails or introduces issues:
- The agent's files should be restorable from git (ensure a clean state before starting).
- Use `git checkout .` or `git reset --hard` if necessary to revert to the pre-upgrade state.

---

## Safety

- Never touch IDENTITY.md, SOUL.md, USER.md, or memory files
- Always show diffs before applying merge-carefully files
- Preserve custom skills and knowledge directories
- If in doubt, keep the agent's version and flag for human review
