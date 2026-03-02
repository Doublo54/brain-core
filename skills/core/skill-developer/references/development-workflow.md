# Skill Development Workflow — Detailed Guide

This document provides step-by-step examples, edge cases, and templates for safely iterating on skills using the skill-developer workflow.

---

## Table of Contents

1. [Walkthrough: Improving banner-studio](#walkthrough-improving-banner-studio)
2. [_dev_manifest.json Format](#_dev_manifestjson-format)
3. [Proposal File Format](#proposal-file-format)
4. [Edge Cases](#edge-cases)
5. [Integration with code-review-orchestrator](#integration-with-code-review-orchestrator)
6. [Testing Tips](#testing-tips)
7. [sync-skills.sh Integration Details](#sync-skillssh-integration-details)

---

## Walkthrough: Improving banner-studio

**Scenario:** Miro wants to add dark theme support to banner-studio.

### Phase 1 — Start

Miro's current file structure (symlinked):
```
agents/miro/skills/banner-studio/
├── SKILL.md → ../../../../shared-skills/specialized/banner-studio/SKILL.md
├── scripts → ../../../../shared-skills/specialized/banner-studio/scripts
├── references → ../../../../shared-skills/specialized/banner-studio/references
├── assets → ../../../../shared-skills/specialized/banner-studio/assets
└── brand → ../../../../brand-assets/banner-studio
```

**Step 1 — Break the symlinks and copy real files:**
```bash
# From the brain workspace root directory
SKILL_DIR="agents/miro/skills/banner-studio"
SOURCE_DIR="shared-skills/specialized/banner-studio"

# Remove symlinks (not -r, they're just links)
rm "$SKILL_DIR/SKILL.md"
rm "$SKILL_DIR/scripts"
rm "$SKILL_DIR/references"
rm "$SKILL_DIR/assets"
# Keep brand symlink — it points to org-specific assets, not shared-skills

# Copy real files
cp "$SOURCE_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"
cp -r "$SOURCE_DIR/scripts" "$SKILL_DIR/scripts"
cp -r "$SOURCE_DIR/references" "$SKILL_DIR/references"
cp -r "$SOURCE_DIR/assets" "$SKILL_DIR/assets"
```

**Step 2 — Create the development manifest:**
```bash
cat > "$SKILL_DIR/_dev_manifest.json" << 'EOF'
{
  "skill": "banner-studio",
  "started_at": "2026-02-15T14:58:00Z",
  "source": "shared-skills/specialized/banner-studio",
  "developer": "miro",
  "reason": "Add dark theme support for night-mode social media posts",
  "changes": []
}
EOF
```

Now Miro's structure looks like:
```
agents/miro/skills/banner-studio/
├── _dev_manifest.json              ← NEW: marks skill as in-development
├── SKILL.md                        ← real file (was symlink)
├── scripts/                        ← real directory (was symlink)
│   ├── generate.py
│   └── setup-banner.sh
├── references/                     ← real directory (was symlink)
│   ├── template-guide.md
│   └── social-platform-specs.md
├── assets/                         ← real directory (was symlink)
│   └── templates/
│       └── minimal-banner.html
└── brand → ../../../../brand-assets/banner-studio  ← KEPT as symlink
```

### Phase 2 — Develop

Miro modifies files freely:

```bash
# Add dark theme flag to generate.py
# Edit: scripts/generate.py
#   - Add --dark-theme argument to argparse
#   - Add dark theme CSS injection logic

# Create new dark theme template
# Create: assets/templates/dark-banner.html

# Update SKILL.md to document dark theme
# Edit: SKILL.md — add dark theme section
```

After each change, update the manifest:
```json
{
  "skill": "banner-studio",
  "started_at": "2026-02-15T14:58:00Z",
  "source": "shared-skills/specialized/banner-studio",
  "developer": "miro",
  "reason": "Add dark theme support for night-mode social media posts",
  "changes": [
    {
      "file": "scripts/generate.py",
      "action": "modified",
      "summary": "Added --dark-theme flag and dark CSS injection",
      "timestamp": "2026-02-15T15:10:00Z"
    },
    {
      "file": "assets/templates/dark-banner.html",
      "action": "added",
      "summary": "Dark theme HTML template with inverted color scheme",
      "timestamp": "2026-02-15T15:25:00Z"
    },
    {
      "file": "SKILL.md",
      "action": "modified",
      "summary": "Documented dark theme usage in skill description",
      "timestamp": "2026-02-15T15:30:00Z"
    }
  ]
}
```

### Phase 3 — Propose

Generate the proposal:

```bash
SKILL_DIR="agents/miro/skills/banner-studio"
SOURCE_DIR="shared-skills/specialized/banner-studio"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Generate diff against original
diff -ruN "$SOURCE_DIR" "$SKILL_DIR" \
  --exclude="_dev_manifest.json" \
  --exclude="brand" \
  > "proposals/banner-studio-${TIMESTAMP}.diff"

# Create the proposal markdown (see template below)
```

Place the proposal at `proposals/banner-studio-20260215-153500.md` and commit to Miro's working branch.

### Phase 4 — Finish

After the human applies changes to brain-core and runs `sync-skills.sh`:

```bash
SKILL_DIR="agents/miro/skills/banner-studio"

# Remove real files
rm "$SKILL_DIR/SKILL.md"
rm -rf "$SKILL_DIR/scripts"
rm -rf "$SKILL_DIR/references"
rm -rf "$SKILL_DIR/assets"

# Restore symlinks
ln -s "../../../../shared-skills/specialized/banner-studio/SKILL.md" "$SKILL_DIR/SKILL.md"
ln -s "../../../../shared-skills/specialized/banner-studio/scripts" "$SKILL_DIR/scripts"
ln -s "../../../../shared-skills/specialized/banner-studio/references" "$SKILL_DIR/references"
ln -s "../../../../shared-skills/specialized/banner-studio/assets" "$SKILL_DIR/assets"

# Remove manifest
rm "$SKILL_DIR/_dev_manifest.json"

# Verify — the synced version should now include dark theme changes
cat "$SKILL_DIR/scripts/generate.py" | grep -q "dark-theme" && echo "✓ Changes synced"
```

---

## _dev_manifest.json Format

```json
{
  "skill": "<skill-name>",
  "started_at": "<ISO 8601 timestamp>",
  "source": "<path relative to org-brain root where original lives>",
  "developer": "<agent-name>",
  "reason": "<human-readable reason for development>",
  "changes": [
    {
      "file": "<relative path within skill dir>",
      "action": "added | modified | removed",
      "summary": "<one-line description of change>",
      "timestamp": "<ISO 8601 timestamp>"
    }
  ]
}
```

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `skill` | yes | Name of the skill being developed |
| `started_at` | yes | When development started (ISO 8601) |
| `source` | yes | Original location (for restore in Phase 4) |
| `developer` | yes | Which agent is doing the development |
| `reason` | yes | Why this skill needs changes |
| `changes` | yes | Array of changes made (starts empty) |
| `changes[].file` | yes | File path relative to skill directory |
| `changes[].action` | yes | One of: `added`, `modified`, `removed` |
| `changes[].summary` | yes | One-line description of the change |
| `changes[].timestamp` | no | When the change was made |

---

## Proposal File Format

Proposals live in the agent's `proposals/` directory and are git-tracked.

**Filename:** `<skill-name>-<YYYYMMDD-HHMMSS>.md`

### Template

```markdown
# Skill Improvement Proposal: <skill-name>

**Developer:** <agent-name>
**Date:** <date>
**Skill:** <skill-name>
**Source:** brain-core/skills/<category>/<skill-name>

---

## Summary

<1-3 sentences describing what changed and why>

## Changes

| File | Action | Description |
|------|--------|-------------|
| scripts/generate.py | modified | Added --dark-theme flag and dark CSS injection |
| assets/templates/dark-banner.html | added | Dark theme HTML template |
| SKILL.md | modified | Documented dark theme usage |

## Diff

<unified diff of all changed files — copy from generated .diff file>

## Testing

### Tests Performed
- [ ] <test 1 description and result>
- [ ] <test 2 description and result>

### Test Output
<relevant output snippets>

## Impact

### Agents Using This Skill
- <agent-1> (via shared-skills symlink)
- <agent-2> (via shared-skills symlink)

### Backward Compatibility
- <notes on whether existing functionality is preserved>
- <any new dependencies or requirements>

### Migration Notes
- <any steps needed after sync (e.g., new brand assets to create)>
```

### Example: Complete Proposal

```markdown
# Skill Improvement Proposal: banner-studio

**Developer:** Miro
**Date:** 2026-02-15
**Skill:** banner-studio
**Source:** brain-core/skills/specialized/banner-studio

---

## Summary

Added dark theme support to banner generation. Banners can now be generated
with a `--dark-theme` flag that inverts the color scheme for night-mode
social media posts.

## Changes

| File | Action | Description |
|------|--------|-------------|
| scripts/generate.py | modified | Added --dark-theme flag and dark CSS injection |
| assets/templates/dark-banner.html | added | Dark theme HTML template (1200x675) |
| SKILL.md | modified | Documented dark theme in usage section |

## Diff

[contents of banner-studio-20260215-153500.diff]

## Testing

### Tests Performed
- [x] Generated banner with --dark-theme flag → correct dark background
- [x] Generated banner without flag → unchanged (backward compatible)
- [x] Dark template renders offline (no CDN dependencies)
- [x] Brand overlay colors apply correctly in dark mode

### Test Output
Successfully generated: /tmp/banner-dark-test.png (1200x675, dark theme)

## Impact

### Agents Using This Skill
- Miro (via shared-skills symlink — will get update on next sync)

### Backward Compatibility
- ✅ Existing commands work unchanged (--dark-theme is optional)
- ✅ No new dependencies (uses existing Playwright installation)

### Migration Notes
- Org-specific brand assets may want to add dark variants to their templates
```

---

## Edge Cases

### 1. sync-skills.sh runs while skill is in development

**What happens:** sync-skills.sh detects `_dev_manifest.json` and **skips** that skill entirely. All other skills sync normally.

**The agent's local copy is preserved.** No work is lost.

```
[WARN] Skipping banner-studio (in development — _dev_manifest.json found)
```

**After development completes:** Remove `_dev_manifest.json` and restore symlinks. The next sync will include any brain-core changes that were applied from the proposal.

### 2. brain-core changes conflict with local changes

**Scenario:** While Miro develops dark theme, another human pushes a different change to banner-studio in brain-core (e.g., fixing a bug in generate.py).

**What happens:**
- Miro's local copy is unaffected (sync skips it)
- When Miro creates the proposal, the diff is against the **original** version (before both changes)
- The human reviewing the proposal sees both changes and resolves conflicts manually
- The human applies the merged result to brain-core

**Best practice:** In the proposal's Impact section, note:
> "brain-core may have received independent changes since development started. Human reviewer should merge carefully."

### 3. Aborting development without proposing

**Scenario:** Miro starts developing but decides the changes aren't worth proposing.

**Steps:**
```bash
SKILL_DIR="agents/miro/skills/banner-studio"

# Remove local copies
rm "$SKILL_DIR/SKILL.md"
rm -rf "$SKILL_DIR/scripts"
rm -rf "$SKILL_DIR/references"
rm -rf "$SKILL_DIR/assets"
rm "$SKILL_DIR/_dev_manifest.json"

# Restore symlinks
ln -s "../../../../shared-skills/specialized/banner-studio/SKILL.md" "$SKILL_DIR/SKILL.md"
ln -s "../../../../shared-skills/specialized/banner-studio/scripts" "$SKILL_DIR/scripts"
ln -s "../../../../shared-skills/specialized/banner-studio/references" "$SKILL_DIR/references"
ln -s "../../../../shared-skills/specialized/banner-studio/assets" "$SKILL_DIR/assets"
```

No proposal created. No changes propagate. Clean exit.

### 4. Agent tries to develop two skills simultaneously

**Rule:** Only ONE skill in development at a time per agent.

**Detection:** Before starting development, check for existing `_dev_manifest.json` files:
```bash
find agents/<agent-name>/skills -name "_dev_manifest.json" -type f
```

If found, the agent must finish or abort the current development before starting a new one.

### 5. Developing a skill that doesn't use symlinks

If the skill has real files (not symlinked from shared-skills), the "break the glass" step is unnecessary — files are already writable. Still create `_dev_manifest.json` for tracking and transparency, and still create a proposal for human review.

---

## Integration with code-review-orchestrator

For high-impact changes, use the code-review-orchestrator skill **before** creating the proposal:

1. Complete Phase 2 (develop & test)
2. Run a focused code review on the changed files:
   - Security review on any script changes
   - Quality review on template/documentation changes
3. Address review findings
4. Then proceed to Phase 3 (propose) — include review results in the Testing section

This is **optional** but recommended for:
- Changes to executable scripts (generate.py, setup scripts)
- Changes that affect multiple agents
- Security-sensitive modifications

---

## Testing Tips

### Script Changes
```bash
# Test generate.py changes in the agent's sandbox
python3 skills/banner-studio/scripts/generate.py \
  --template skills/banner-studio/assets/templates/dark-banner.html \
  --brand-dir skills/banner-studio/brand \
  --output /tmp/test-banner.png \
  --dark-theme

# Verify output
ls -la /tmp/test-banner.png
```

### SKILL.md Changes
- Read the modified SKILL.md and verify instructions are clear
- Check that triggers and description accurately reflect new capabilities
- Ensure backward compatibility with existing documented commands

### Template Changes
- Render templates with Playwright to verify they display correctly
- Test offline (no CDN dependencies)
- Verify template variables (`{{variable}}`) are documented
- Test with and without brand overlay

### Reference Documentation
- Verify all links resolve correctly
- Check examples are accurate and runnable
- Ensure new features are documented in the right reference files

---

## sync-skills.sh Integration Details

### How sync currently works

```
brain-core/skills/{category}/{skill}/
    → rsync --checksum --delete →
shared-skills/{category}/{skill}/
    → symlinks →
agents/*/skills/{skill}/
```

### Required modification to sync_skill()

Add a `_dev_manifest.json` check at the **destination** (shared-skills or agent skill dir):

```bash
# In the sync_skill() function, add before the rsync call:
sync_skill() {
    local category="$1"
    local skill="$2"
    local src="$BRAIN_CORE_PATH/skills/$category/$skill/"
    local dst="$SHARED_SKILLS/$category/$skill/"

    # ── NEW: Check if any agent has this skill in development ──
    for agent_skill in "$REPO_ROOT"/agents/*/skills/"$skill"; do
        if [[ -f "$agent_skill/_dev_manifest.json" ]]; then
            local dev_agent
            dev_agent=$(python3 -c "import json; print(json.load(open('$agent_skill/_dev_manifest.json'))['developer'])" 2>/dev/null || echo "unknown")
            log_warn "Skipping $skill — in development by $dev_agent"
            log_warn "  Manifest: $agent_skill/_dev_manifest.json"
            ((SKILLS_SYNCED++)) || true
            return
        fi
    done

    # ... existing rsync logic continues ...
}
```

### Why skip at the agent level, not shared-skills level

The sync still updates `shared-skills/` — that's fine since it's just a cache. The skip prevents **agent-level symlinks** from being restored over the agent's local working copy.

**Alternative approach (simpler):** Don't modify sync-skills.sh at all. Since Phase 1 replaces symlinks with real files, rsync to shared-skills won't affect the agent's local copy (it's no longer symlinked). The `_dev_manifest.json` mainly serves as:
- A **signal to the agent** that development is in progress
- A **signal to humans** scanning the repo
- A **guard** against accidental symlink restoration

### Verification after sync

After sync runs, verify the development skill is intact:
```bash
# Should still be a real file, not a symlink
test -f "agents/miro/skills/banner-studio/_dev_manifest.json" && echo "✓ Still in development"
test ! -L "agents/miro/skills/banner-studio/SKILL.md" && echo "✓ Still a real file (not symlink)"
```
