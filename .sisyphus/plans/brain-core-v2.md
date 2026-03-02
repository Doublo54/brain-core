# brain-core v2: Finalization + defizoo-brain Preparation

## TL;DR

> **Quick Summary**: Finalize brain-core as a complete AI orchestration platform by restructuring skills (three-tier), trimming the template, extracting Carpincho's battle-tested orchestration toolkit (~8,900 lines), and updating the Dockerfile. Then prepare a new defizoo-brain workspace repo with 4 curated agent brains.
> 
> **Deliverables**:
> - Three-tier skills architecture (core/behavioral/specialized)
> - Trimmed template (~20% size reduction)
> - Extracted orchestration scripts (14 scripts → `/opt/scripts/`)
> - Extracted Discord pipe integration (TypeScript → `/opt/integrations/`)
> - Updated Dockerfile with new scripts and integrations
> - Updated create-agent and upgrade-agent skills
> - New defizoo-brain repo structure with 4 agents (ApeAI, GregAIlia, Carpincho, Carl)
> - Curated agent content (identity, knowledge, skills selection)
> 
> **Estimated Effort**: XL
> **Parallel Execution**: YES — 5 waves
> **Critical Path**: Task 3 (script path resolution) → Task 4 (script extraction) → Task 7 (Dockerfile) → Task 8 (docs) → Task 10 (defizoo scaffold)

---

## Context

### Original Request
Finalize brain-core with new context from old brain repositories (defizoo-brain, GregAIlia-brain, Carpincho-brain). Prepare to set up a fresh defizoo-brain accounting for all learnings, the existence of brain-core, and the new structure.

### Interview Summary
**Key Discussions**:
- **Skills architecture**: Three-tier (core + behavioral + specialized) — different categories serve different audiences
- **Carpincho extraction**: Full extraction of ~8,900 lines of battle-tested orchestration code
- **Template trimming**: Moderate — remove unused, move OpenClaw-specific to docs/
- **Deployment model**: brain-core = Docker image (rebuild/redeploy). defizoo-brain = workspace on volume (immediate). NO submodule.
- **Scripts deployment**: Generic scripts baked into image. Agent-specific config in workspace.
- **Linking**: copy-on-create + upgrade-agent for skill propagation
- **Agent migration**: All 4 agents, fresh start with manually curated content
- **Discord pipe**: Baked into image as generic integration

**Research Findings**:
- Template has 26 files (~110KB); 9 classified as noise (~26KB)
- skills/ and template/skills/ serve different purposes by design (operational vs behavioral)
- Carpincho-brain has 14 scripts (4,528 lines), 2 unique skills (555 lines), Discord pipe (1,248 lines TypeScript)
- Scripts have 5 hardcoded coupling points (GITHUB_TOKEN_carpincho, workspace paths, agent names)
- 70% of scripts are already generic; 30% needs parameterization
- defizoo-brain had 4 active agents + 1 stub (team-coordinator, dropped)

### Metis Review
**Identified Gaps** (addressed):
- **CRITICAL: Script relative path resolution** — Scripts use `SCRIPT_DIR/../state/` patterns. When baked at `/opt/scripts/`, this breaks. Resolution: Scripts receive `WORKSPACE` env var; all relative paths resolve via `$WORKSPACE/`.
- **CRITICAL: Per-agent state isolation** — Multiple agents sharing scripts need separate `state/` directories. Resolution: `$WORKSPACE/state/` per agent.
- **HIGH: OpenClaw extensions** — discord-roles, telegramuser, hindsight-retain not addressed. Resolution: discord-roles → brain-core (generic). telegramuser → defizoo-brain (business). hindsight-retain → already managed as submodule.
- **HIGH: Specialized skills discovery** — create-agent only copies from template/; doesn't know about specialized skills. Resolution: Update create-agent with `--skills` parameter.
- **MEDIUM: upgrade-agent consistency** — Template file moves (BOOT.md, CONFIG_BACKUP.md) break upgrade-agent's file classification. Resolution: Update upgrade-agent after template changes.
- **MEDIUM: README scope expansion** — Adding scripts/integrations contradicts README's "infrastructure only" claim. Resolution: Update README.
- **MEDIUM: team-coordinator agent** — 5th agent from old defizoo-brain. Resolution: Dropped (was a sandboxed GregAIlia clone, not needed).
- **LOW: Agent ID mapping** — Carl's old ID was `sales`. Resolution: Use `carl` as new ID.

---

## Work Objectives

### Core Objective
Transform brain-core into a complete AI orchestration platform with three-tier skills, production-grade orchestration scripts, and Discord streaming. Then scaffold a new defizoo-brain workspace with 4 curated agent brains.

### Concrete Deliverables
- Restructured `skills/` directory (core/ + behavioral/ + specialized/)
- Trimmed `template/` (LEARNINGS.md, mental-models/ removed; BOOT.md, CONFIG_BACKUP.md moved)
- Extracted and generalized orchestration scripts at `scripts/orchestration/`
- Extracted Discord pipe at `integrations/opencode-discord-pipe/`
- Extracted orchestration docs and post-mortems
- Updated Dockerfile with new COPY lines and npm install
- Updated create-agent, manage-agent, upgrade-agent skills
- Updated README.md
- New defizoo-brain repo structure with 4 curated agents
- Agent-specific config templates (repo-configs, brain.yaml)

### Definition of Done
- [ ] `docker buildx build --platform linux/amd64 --target gateway -f docker/Dockerfile .` exits 0
- [ ] `docker run --rm test-gateway ls /opt/scripts/orchestration/` shows all 14+ scripts
- [ ] `docker run --rm test-gateway ls /opt/integrations/opencode-discord-pipe/` shows pipe files
- [ ] `ls skills/core/ skills/behavioral/ skills/specialized/` shows all 7 skills
- [ ] `test ! -f template/LEARNINGS.md` (removed)
- [ ] `test -f docs/openclaw/BOOT.md` (moved)
- [ ] `grep -r "carpincho\|GITHUB_TOKEN_carpincho" scripts/orchestration/ | grep -v test` returns 0 matches
- [ ] defizoo-brain directory has 4 agent directories with identity files
- [ ] `grep -rE "ghp_|gho_|sk-" . --include="*.md" --include="*.json" --include="*.sh" --include="*.ts" | grep -v node_modules | grep -v .git` returns 0 matches (no secrets)

### Must Have
- Three-tier skills structure
- All 14 Carpincho scripts extracted and generalized
- Discord pipe extracted
- Dockerfile updated and builds successfully
- create-agent updated for specialized skills
- defizoo-brain scaffold with all 4 agents

### Must NOT Have (Guardrails)
- DO NOT change script behavior during extraction — generalization = parameterization only
- DO NOT modify files in `brains-old/` — read-only reference
- DO NOT add new template files during trimming — only remove/move
- DO NOT restructure Dockerfile stages or optimize layers — only add COPY lines
- DO NOT add npm packages beyond tsx/typescript for the Discord pipe
- DO NOT curate knowledge content in Phase 1 (that's Phase 2)
- DO NOT fix bugs or refactor logic in extracted scripts
- DO NOT rename OHO agent names (prometheus, atlas, sisyphus) — those are platform conventions, not hardcoded identity
- DO NOT delete brains-old/ directory after extraction

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**

### Test Decision
- **Infrastructure exists**: NO
- **Automated tests**: None (Docker builds + grep validations)
- **Framework**: N/A

### Agent-Executed QA Scenarios (MANDATORY)

| Type | Tool | How Agent Verifies |
|------|------|-------------------|
| **Dockerfile changes** | Bash (docker buildx) | Build, assert exit 0, verify file presence |
| **Script extraction** | Bash (grep, ls) | Check file existence, permissions, no hardcoded values |
| **Skills structure** | Bash (ls, find) | Verify directory layout matches spec |
| **Template changes** | Bash (test, grep) | Verify removals and moves |
| **defizoo-brain** | Bash (ls, find) | Verify directory structure |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Skills three-tier restructure
├── Task 2: Template trimming
└── Task 3: Script path resolution design (CRITICAL — blocks Task 4)

Wave 2 (After Wave 1):
├── Task 4: Script extraction + generalization (depends: 3)
├── Task 5: Discord pipe extraction
└── Task 6: Orchestration docs extraction

Wave 3 (After Wave 2):
├── Task 7: Dockerfile update (depends: 4, 5)
└── Task 8: Skills & docs updates (depends: 1, 2, 4)

Wave 4 (After Wave 3):
├── Task 9: README & final brain-core cleanup (depends: all above)

Wave 5 (Phase 2 — After Wave 4):
├── Task 10: Scaffold defizoo-brain repo structure
├── Task 11: Curate agent identities (ApeAI, GregAIlia, Carpincho, Carl)
├── Task 12: Curate shared knowledge base
├── Task 13: Agent skills selection + config
└── Task 14: Extensions setup (discord-roles, telegramuser)

Critical Path: Task 3 → Task 4 → Task 7 → Task 9 → Task 10
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 8 | 2, 3 |
| 2 | None | 8 | 1, 3 |
| 3 | None | 4 | 1, 2 |
| 4 | 3 | 7, 8 | 5, 6 |
| 5 | None (wave timing) | 7 | 4, 6 |
| 6 | None (wave timing) | 8 | 4, 5 |
| 7 | 4, 5 | 9 | 8 |
| 8 | 1, 2, 4, 6 | 9 | 7 |
| 9 | 7, 8 | 10 | None |
| 10 | 9 | 11-14 | None |
| 11 | 10 | None | 12, 13, 14 |
| 12 | 10 | None | 11, 13, 14 |
| 13 | 10 | None | 11, 12, 14 |
| 14 | 10 | None | 11, 12, 13 |

---

## TODOs

### PHASE 1: brain-core Finalization

---

- [x] 1. Restructure Skills to Three-Tier Architecture

  **What to do**:
  - Create `skills/core/` directory — move `create-agent/`, `manage-agent/`, `upgrade-agent/` into it
  - Create `skills/behavioral/` directory — move `template/skills/memory-brain/` and `template/skills/proactive-agent-behavior/` into it
  - Create `skills/specialized/` directory — copy `brains-old/crapincho-brain/skills/coding-orchestrator/` and `brains-old/crapincho-brain/skills/code-review-orchestrator/` into it
  - Update `template/skills/` to reference new locations (symlinks from template/skills/ → skills/behavioral/ for backward compat during copy-on-create)
  - Verify all SKILL.md files have correct relative paths to reference.md files

  **Must NOT do**:
  - Do NOT modify SKILL.md content — only move files
  - Do NOT create new skills
  - Do NOT change the template/skills/ copy mechanism yet (create-agent update is Task 8)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Task 8
  - **Blocked By**: None

  **References**:
  - `skills/create-agent/` — Current location of operational skills
  - `skills/manage-agent/` — Current location
  - `skills/upgrade-agent/` — Current location
  - `template/skills/memory-brain/` — Current location of behavioral skills
  - `template/skills/proactive-agent-behavior/` — Current location
  - `brains-old/crapincho-brain/skills/coding-orchestrator/SKILL.md` — Source for specialized skill (431 lines)
  - `brains-old/crapincho-brain/skills/code-review-orchestrator/SKILL.md` — Source for specialized skill (124 lines)

  **WHY Each Reference Matters**:
  - These are exactly the files being moved. The executor needs to know current locations and destinations.

  **Acceptance Criteria**:
  - [ ] `ls skills/core/create-agent skills/core/manage-agent skills/core/upgrade-agent` → all exist
  - [ ] `ls skills/behavioral/memory-brain skills/behavioral/proactive-agent-behavior` → all exist
  - [ ] `ls skills/specialized/coding-orchestrator skills/specialized/code-review-orchestrator` → all exist
  - [ ] `template/skills/memory-brain/SKILL.md` still exists (backward compat — symlink or copy)
  - [ ] `template/skills/proactive-agent-behavior/SKILL.md` still exists (backward compat)
  - [ ] No broken references in any SKILL.md (grep for old paths returns 0)

  **Agent-Executed QA Scenarios**:
  ```
  Scenario: Three-tier structure exists
    Tool: Bash
    Steps:
      1. ls skills/core/ → contains create-agent, manage-agent, upgrade-agent
      2. ls skills/behavioral/ → contains memory-brain, proactive-agent-behavior
      3. ls skills/specialized/ → contains coding-orchestrator, code-review-orchestrator
      4. Each skill directory contains at minimum SKILL.md
    Expected Result: All 7 skills in correct tiers
    Evidence: ls output captured

  Scenario: Template backward compatibility
    Tool: Bash
    Steps:
      1. test -f template/skills/memory-brain/SKILL.md → exists
      2. test -f template/skills/proactive-agent-behavior/SKILL.md → exists
    Expected Result: Template still has behavioral skills (via symlink or copy)
  ```

  **Commit**: YES
  - Message: `refactor: restructure skills to three-tier architecture (core/behavioral/specialized)`
  - Files: `skills/core/`, `skills/behavioral/`, `skills/specialized/`, `template/skills/`

---

- [x] 2. Template Moderate Trim

  **What to do**:
  - Delete `template/LEARNINGS.md` (agents rarely maintain this)
  - Delete `template/mental-models/.gitkeep` (never populated, never referenced)
  - Move `template/BOOT.md` → `docs/openclaw/BOOT.md`
  - Move `template/CONFIG_BACKUP.md` → `docs/openclaw/CONFIG_BACKUP.md`
  - Create `docs/openclaw/` directory if it doesn't exist

  **Must NOT do**:
  - Do NOT remove bootstrap/ suite (self-deletes after first run)
  - Do NOT remove PLAYBOOK.md, HEARTBEAT.md, or any behavioral files
  - Do NOT add new template files
  - Do NOT modify content of moved files

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: Task 8 (upgrade-agent needs updating)
  - **Blocked By**: None

  **References**:
  - `template/LEARNINGS.md` — File to delete (335 bytes, empty stub)
  - `template/mental-models/.gitkeep` — File to delete (0 bytes, never used)
  - `template/BOOT.md` — File to move (542 bytes, OpenClaw restart checklist)
  - `template/CONFIG_BACKUP.md` — File to move (5.5KB, OpenClaw config backup process)
  - `skills/core/upgrade-agent/SKILL.md:19-21` — Lists BOOT.md and CONFIG_BACKUP.md as "safe to overwrite" — needs update in Task 8

  **Acceptance Criteria**:
  - [ ] `test ! -f template/LEARNINGS.md` → file removed
  - [ ] `test ! -d template/mental-models` → directory removed
  - [ ] `test ! -f template/BOOT.md` → moved away
  - [ ] `test ! -f template/CONFIG_BACKUP.md` → moved away
  - [ ] `test -f docs/openclaw/BOOT.md` → moved here
  - [ ] `test -f docs/openclaw/CONFIG_BACKUP.md` → moved here
  - [ ] `ls template/ | wc -l` → count reduced vs baseline

  **Agent-Executed QA Scenarios**:
  ```
  Scenario: Template trimmed correctly
    Tool: Bash
    Steps:
      1. test ! -f template/LEARNINGS.md → removed
      2. test ! -d template/mental-models → removed
      3. test -f docs/openclaw/BOOT.md → moved
      4. test -f docs/openclaw/CONFIG_BACKUP.md → moved
      5. diff <(cat docs/openclaw/BOOT.md) <(git show HEAD:template/BOOT.md) → identical content
    Expected Result: Files removed and moved without content changes
  ```

  **Commit**: YES
  - Message: `chore: trim template — remove unused files, move OpenClaw-specific to docs/`
  - Files: `template/LEARNINGS.md` (deleted), `template/mental-models/` (deleted), `template/BOOT.md` (moved), `template/CONFIG_BACKUP.md` (moved), `docs/openclaw/`

---

- [x] 3. Design Script Path Resolution Strategy

  **What to do**:
  - This is a DESIGN task, not implementation. Create a document at `docs/orchestration-scripts.md` that specifies:
    - Scripts live at `/opt/scripts/orchestration/` in the Docker image (read-only)
    - All scripts receive workspace context via `WORKSPACE` environment variable
    - `WORKSPACE` resolves to the agent's brain directory (e.g., `/home/node/.openclaw/workspaces/carpincho/`)
    - Per-agent state lives at `$WORKSPACE/state/` (tasks.json, alerts.json, monitor PID)
    - Per-agent config lives at `$WORKSPACE/config/` (repo-configs, templates)
    - Scripts discover workspace via: (1) `$WORKSPACE` env var, (2) `$1` positional argument, (3) current working directory
    - GitHub token resolution: `$GITHUB_TOKEN` (shared) or `$GITHUB_TOKEN_${AGENT_ID}` (per-agent override)
  - Document the refactoring pattern for each `SCRIPT_DIR/../` usage:
    - `SCRIPT_DIR="../state"` → `STATE_DIR="${WORKSPACE}/state"`
    - `SCRIPT_DIR="../templates"` → `TEMPLATES_DIR="${WORKSPACE}/config/templates"`
    - `SCRIPT_DIR/../repo-configs/` → `REPO_CONFIGS_DIR="${WORKSPACE}/config/repo-configs"`
  - Verify all 14 scripts for relative path patterns and document each instance

  **Must NOT do**:
  - Do NOT implement the changes yet (that's Task 4)
  - Do NOT modify any script files
  - Do NOT change the Dockerfile

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Task 4 (must be completed before script extraction)
  - **Blocked By**: None

  **References**:
  - `brains-old/crapincho-brain/scripts/task-manager.sh:29` — `STATE_DIR="${SCRIPT_DIR}/../state"` pattern
  - `brains-old/crapincho-brain/scripts/monitor.sh:27` — Hardcoded `/home/node/.openclaw/workspaces/carpincho`
  - `brains-old/crapincho-brain/scripts/daemon-monitor.sh:8` — Hardcoded workspace path
  - `brains-old/crapincho-brain/scripts/setup-workspace.sh` — Uses GITHUB_TOKEN_carpincho
  - `brains-old/crapincho-brain/scripts/github-pr.sh` — Uses GITHUB_TOKEN_carpincho
  - `brains-old/crapincho-brain/scripts/cleanup-workspace.sh` — Uses GITHUB_TOKEN_carpincho
  - `brains-old/crapincho-brain/skills/coding-orchestrator/SKILL.md:148` — Script path reference table

  **WHY Each Reference Matters**:
  - Each file contains hardcoded values that must be parameterized. The design doc maps every instance to its replacement pattern.

  **Acceptance Criteria**:
  - [ ] `docs/orchestration-scripts.md` exists with path resolution spec
  - [ ] Document covers ALL 14 scripts with their `SCRIPT_DIR/../` patterns
  - [ ] Document specifies WORKSPACE discovery order (env var → arg → cwd)
  - [ ] Document specifies per-agent state isolation strategy
  - [ ] Document specifies GitHub token resolution strategy

  **Agent-Executed QA Scenarios**:
  ```
  Scenario: Design doc is comprehensive
    Tool: Bash
    Steps:
      1. grep -c "WORKSPACE" docs/orchestration-scripts.md → ≥ 10 mentions
      2. grep -c "SCRIPT_DIR" docs/orchestration-scripts.md → ≥ 5 (documenting what to replace)
      3. grep -c "task-manager\|monitor\|opencode-session\|github-pr" docs/orchestration-scripts.md → ≥ 8 (covers key scripts)
    Expected Result: Design doc covers all scripts and patterns
  ```

  **Commit**: YES
  - Message: `docs: add orchestration scripts path resolution design spec`
  - Files: `docs/orchestration-scripts.md`

---

- [x] 4. Extract and Generalize Orchestration Scripts

  **What to do**:
  - Copy all 14 scripts from `brains-old/crapincho-brain/scripts/` to `scripts/orchestration/`
  - Apply the path resolution design from Task 3:
    - Replace all `SCRIPT_DIR="../state"` patterns with `STATE_DIR="${WORKSPACE:?WORKSPACE env var required}/state"`
    - Replace all `SCRIPT_DIR="../templates"` with `TEMPLATES_DIR="${WORKSPACE}/config/templates"`
    - Replace all `SCRIPT_DIR/../repo-configs/` with `REPO_CONFIGS_DIR="${WORKSPACE}/config/repo-configs"`
  - Replace hardcoded agent-specific values:
    - `GITHUB_TOKEN_carpincho` → `GITHUB_TOKEN` with fallback: `${GITHUB_TOKEN:-${GITHUB_TOKEN_${AGENT_ID:-default}}}`
    - `/home/node/.openclaw/workspaces/carpincho` → `$WORKSPACE`
  - Add a header comment to each script: `# brain-core orchestration script — see docs/orchestration-scripts.md`
  - Keep agent name references to OpenCode agents (prometheus, atlas, sisyphus) — these are platform conventions, not hardcoded identity
  - Copy templates: `brains-old/crapincho-brain/templates/plan-prompt.md` and `fix-prompt.md` → `scripts/orchestration/templates/`
  - Ensure all scripts are executable (chmod +x)

  **Must NOT do**:
  - Do NOT change script logic — parameterization ONLY
  - Do NOT fix bugs or add error handling
  - Do NOT refactor code structure
  - Do NOT rename scripts
  - Do NOT modify test scripts (test-orchestrator.sh, test-approval-gate.sh) beyond path changes

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: Task 7 (Dockerfile), Task 8 (docs)
  - **Blocked By**: Task 3 (path design)

  **References**:
  - `brains-old/crapincho-brain/scripts/` — All 14 source scripts
  - `docs/orchestration-scripts.md` — Path resolution design spec (from Task 3)
  - `brains-old/crapincho-brain/skills/coding-orchestrator/SKILL.md:146-168` — Script reference table (update paths)
  - `brains-old/crapincho-brain/templates/` — plan-prompt.md, fix-prompt.md

  **WHY Each Reference Matters**:
  - Source scripts are what we're copying. Design doc tells us how to parameterize. Skill reference table needs path updates.

  **Acceptance Criteria**:
  - [ ] `ls scripts/orchestration/` → lists all 14 scripts
  - [ ] `ls scripts/orchestration/templates/` → plan-prompt.md, fix-prompt.md
  - [ ] All scripts are executable: `find scripts/orchestration/ -name "*.sh" ! -perm -u+x` → empty
  - [ ] `grep -r "carpincho" scripts/orchestration/ | grep -v test | grep -v ".bak"` → 0 matches
  - [ ] `grep -r "GITHUB_TOKEN_carpincho" scripts/orchestration/` → 0 matches
  - [ ] `grep -r "/home/node/.openclaw/workspaces/carpincho" scripts/orchestration/` → 0 matches
  - [ ] `grep -c "WORKSPACE" scripts/orchestration/task-manager.sh` → ≥ 1
  - [ ] `sh -n scripts/orchestration/task-manager.sh` → exit 0 (valid syntax)
  - [ ] `sh -n scripts/orchestration/monitor.sh` → exit 0

  **Agent-Executed QA Scenarios**:
  ```
  Scenario: All scripts extracted and generalized
    Tool: Bash
    Steps:
      1. count=$(ls scripts/orchestration/*.sh | wc -l) → ≥ 14
      2. grep -r "carpincho" scripts/orchestration/ | grep -v test → empty
      3. grep -r "GITHUB_TOKEN_carpincho" scripts/orchestration/ → empty
      4. for f in scripts/orchestration/*.sh; do sh -n "$f" || echo "SYNTAX ERROR: $f"; done → no errors
    Expected Result: All scripts present, generalized, syntactically valid

  Scenario: No agent-specific paths remain
    Tool: Bash
    Steps:
      1. grep -r "/home/node/.openclaw/workspaces/carpincho" scripts/orchestration/ → empty
      2. grep -c "WORKSPACE" scripts/orchestration/task-manager.sh → ≥ 1
      3. grep -c "WORKSPACE" scripts/orchestration/monitor.sh → ≥ 1
    Expected Result: All workspace paths use WORKSPACE env var
  ```

  **Commit**: YES
  - Message: `feat: extract and generalize Carpincho orchestration scripts`
  - Files: `scripts/orchestration/` (14 scripts + templates)

---

- [x] 5. Extract Discord Pipe Integration

  **What to do**:
  - Copy `brains-old/crapincho-brain/opencode-discord-pipe/` → `integrations/opencode-discord-pipe/`
  - Generalize hardcoded paths:
    - `watchdog-cron.sh` hardcoded workspace path → use `PIPE_DIR` env var
    - `DISCORD_BOT_TOKEN_2` fallback → `DISCORD_BOT_TOKEN`
  - Keep package.json, all TypeScript files, daemon.sh, watchdog.sh, README.md
  - Ensure package.json has only necessary dependencies (tsx, typescript, discord.js)

  **Must NOT do**:
  - Do NOT add new features to the pipe
  - Do NOT change event routing or channel logic
  - Do NOT add new npm packages

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: Task 7 (Dockerfile)
  - **Blocked By**: None (wave timing only)

  **References**:
  - `brains-old/crapincho-brain/opencode-discord-pipe/` — All source files
  - `brains-old/crapincho-brain/opencode-discord-pipe/README.md` — Architecture docs
  - `brains-old/crapincho-brain/opencode-discord-pipe/watchdog-cron.sh` — Contains hardcoded path

  **Acceptance Criteria**:
  - [ ] `ls integrations/opencode-discord-pipe/` → pipe.ts, discord.ts, formatter.ts, config.ts, daemon.sh, watchdog.sh, README.md, package.json
  - [ ] `grep -r "carpincho" integrations/opencode-discord-pipe/` → 0 matches
  - [ ] `cat integrations/opencode-discord-pipe/package.json | python3 -c "import sys,json; deps=json.load(sys.stdin).get('dependencies',{}); print(len(deps))"` → ≤ 5

  **Commit**: YES
  - Message: `feat: extract Discord pipe integration from Carpincho`
  - Files: `integrations/opencode-discord-pipe/`

---

- [x] 6. Extract Orchestration Documentation

  **What to do**:
  - Copy `brains-old/crapincho-brain/docs/LEARNINGS-2026-02-09-code-review-failure.md` → `docs/orchestration/LEARNINGS-code-review-failure.md`
  - Copy `brains-old/crapincho-brain/docs/gateway-approval-config.yaml` → `docs/orchestration/gateway-approval-config.yaml`
  - Copy `brains-old/crapincho-brain/plans/opencode-orchestrator.md` → `docs/orchestration/architecture.md` (rename for clarity)
  - Create `docs/orchestration/` directory
  - Update any internal references in copied docs to reflect new paths

  **Must NOT do**:
  - Do NOT rewrite documentation content
  - Do NOT add new documentation

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Task 8
  - **Blocked By**: None

  **References**:
  - `brains-old/crapincho-brain/docs/LEARNINGS-2026-02-09-code-review-failure.md` — Critical post-mortem
  - `brains-old/crapincho-brain/docs/gateway-approval-config.yaml` — Approval gate config
  - `brains-old/crapincho-brain/plans/opencode-orchestrator.md` — 1,130-line architecture doc

  **Acceptance Criteria**:
  - [ ] `ls docs/orchestration/` → LEARNINGS-code-review-failure.md, gateway-approval-config.yaml, architecture.md
  - [ ] `wc -l docs/orchestration/architecture.md` → ≥ 1000 lines (comprehensive)

  **Commit**: YES
  - Message: `docs: extract orchestration documentation and post-mortems`
  - Files: `docs/orchestration/`

---

- [x] 7. Update Dockerfile for New Scripts and Integrations

  **What to do**:
  - Add COPY line for `scripts/orchestration/` → `/opt/scripts/orchestration/` in the gateway target
  - Add COPY line for `integrations/opencode-discord-pipe/` → `/opt/integrations/opencode-discord-pipe/`
  - Add `RUN cd /opt/integrations/opencode-discord-pipe && npm install --production` in the gateway build
  - Ensure scripts have execute permissions: `RUN chmod +x /opt/scripts/orchestration/*.sh`
  - Keep changes minimal — only COPY and RUN lines, no stage restructuring

  **Must NOT do**:
  - Do NOT restructure Dockerfile stages
  - Do NOT optimize layer caching
  - Do NOT switch base images
  - Do NOT add packages beyond what's needed for the pipe

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (partially)
  - **Parallel Group**: Wave 3 (with Task 8)
  - **Blocks**: Task 9
  - **Blocked By**: Tasks 4, 5

  **References**:
  - `docker/Dockerfile:149-171` — Current gateway target where COPY lines go
  - `docker/Dockerfile:132-148` — Current COPY patterns to follow
  - `integrations/opencode-discord-pipe/package.json` — npm install target

  **Acceptance Criteria**:
  - [ ] `docker buildx build --platform linux/amd64 --target gateway -f docker/Dockerfile .` → exit 0
  - [ ] `docker run --rm test-gateway ls /opt/scripts/orchestration/task-manager.sh` → file exists
  - [ ] `docker run --rm test-gateway ls /opt/integrations/opencode-discord-pipe/node_modules/` → directory exists
  - [ ] `docker run --rm test-gateway bash /opt/scripts/orchestration/task-manager.sh --help 2>&1` → shows usage (not "file not found")

  **Agent-Executed QA Scenarios**:
  ```
  Scenario: Gateway image contains orchestration scripts
    Tool: Bash
    Steps:
      1. docker buildx build --platform linux/amd64 --target gateway -t test-gateway -f docker/Dockerfile .
      2. Assert: Exit code 0
      3. docker run --rm test-gateway ls /opt/scripts/orchestration/ | wc -l → ≥ 14
      4. docker run --rm test-gateway ls /opt/integrations/opencode-discord-pipe/pipe.ts → exists
      5. docker run --rm test-gateway test -x /opt/scripts/orchestration/task-manager.sh → exit 0
    Expected Result: All scripts and integrations present and executable
  ```

  **Commit**: YES
  - Message: `feat: add orchestration scripts and Discord pipe to Docker image`
  - Files: `docker/Dockerfile`

---

- [x] 8. Update Skills and Documentation for New Structure

  **What to do**:
  - Update `skills/core/upgrade-agent/SKILL.md`:
    - Remove BOOT.md and CONFIG_BACKUP.md from "safe to overwrite" list (they moved to docs/)
    - Remove LEARNINGS.md and mental-models/ references
    - Add behavioral skills path update (skills/behavioral/ instead of template/skills/)
  - Update `skills/core/create-agent/SKILL.md`:
    - Add `--skills` parameter support for specialized skills (coding-orchestrator, code-review-orchestrator)
    - Document that behavioral skills are always copied; specialized are optional
    - Update template source path references
  - Update `skills/core/create-agent/reference.md`:
    - Add specialized skills section
    - Update path references for three-tier structure
  - Update `skills/specialized/coding-orchestrator/SKILL.md`:
    - Update script path references from `scripts/` to `/opt/scripts/orchestration/`
    - Update workspace path references to use `$WORKSPACE`

  **Must NOT do**:
  - Do NOT change skill logic or workflow — only update references
  - Do NOT add new features to skills

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 7)
  - **Blocks**: Task 9
  - **Blocked By**: Tasks 1, 2, 4, 6

  **References**:
  - `skills/core/upgrade-agent/SKILL.md` — File classification list needs updating
  - `skills/core/create-agent/SKILL.md` — Template copy logic needs specialized skills
  - `skills/core/create-agent/reference.md` — Path references and skills section
  - `skills/specialized/coding-orchestrator/SKILL.md` — Script path table at line 146-168
  - `docs/orchestration-scripts.md` — Path resolution spec (from Task 3)

  **Acceptance Criteria**:
  - [ ] `grep -c "BOOT.md\|CONFIG_BACKUP.md\|LEARNINGS.md\|mental-models" skills/core/upgrade-agent/SKILL.md` → 0
  - [ ] `grep -c "specialized" skills/core/create-agent/SKILL.md` → ≥ 1 (references specialized skills)
  - [ ] `grep -c "/opt/scripts/orchestration" skills/specialized/coding-orchestrator/SKILL.md` → ≥ 3
  - [ ] `grep -c "WORKSPACE" skills/specialized/coding-orchestrator/SKILL.md` → ≥ 2

  **Commit**: YES
  - Message: `fix: update skill references for three-tier structure and new script paths`
  - Files: `skills/core/upgrade-agent/SKILL.md`, `skills/core/create-agent/SKILL.md`, `skills/core/create-agent/reference.md`, `skills/specialized/coding-orchestrator/SKILL.md`

---

- [x] 9. Update README and Final brain-core Cleanup

  **What to do**:
  - Update `README.md`:
    - Add orchestration scripts section to "What's Inside" tree
    - Add integrations section
    - Update skills section for three-tier layout
    - Update "What Does NOT Belong Here" — expand scope description (scripts and integrations ARE allowed now)
  - Verify no broken links across all docs
  - Verify `docker compose -f docker/docker-compose.dev.yml config --quiet` still passes
  - Run final secrets scan across entire repo

  **Must NOT do**:
  - Do NOT add deployment instructions for orchestration (that's per-org)
  - Do NOT rewrite README from scratch — surgical updates only

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (sequential)
  - **Blocks**: Task 10
  - **Blocked By**: Tasks 7, 8

  **References**:
  - `README.md` — Current README to update
  - `docs/` — All docs for link verification
  - `docker/docker-compose.dev.yml` — Dev compose validation

  **Acceptance Criteria**:
  - [ ] `grep -c "orchestration\|scripts/orchestration" README.md` → ≥ 2
  - [ ] `grep -c "integrations" README.md` → ≥ 1
  - [ ] `grep -c "core/\|behavioral/\|specialized/" README.md` → ≥ 1
  - [ ] `docker compose -f docker/docker-compose.dev.yml config --quiet` → exit 0
  - [ ] `grep -rE "ghp_|gho_|sk-|xoxb-" . --include="*.md" --include="*.json" --include="*.sh" --include="*.ts" | grep -v node_modules | grep -v .git | grep -v brains-old` → 0 matches

  **Commit**: YES
  - Message: `docs: update README for orchestration scripts, integrations, and three-tier skills`
  - Files: `README.md`

---

### PHASE 2: defizoo-brain Preparation

---

- [x] 10. Scaffold defizoo-brain Repository Structure

  **What to do**:
  - Create `defizoo-brain/` directory at repo root (or as a sibling — TBD based on deployment model)
  - Create directory structure:
    ```
    defizoo-brain/
    ├── agents/
    │   ├── apeai/          # OpenClaw orchestrator
    │   ├── gregailia/      # HR / Head of Staff
    │   ├── carpincho/      # Coding guru
    │   └── carl/           # Sales & BD
    ├── knowledge/
    │   ├── defizoo/        # Org structure, culture, products
    │   ├── team/           # Roster, profiles, policies
    │   ├── apeguru/        # Personal OS, identity, writing voice
    │   └── discord/        # Channel map, roster IDs
    ├── extensions/
    │   ├── discord-roles/  # Discord role management (from GregAIlia)
    │   └── telegramuser/   # Telegram integration (for Carl)
    ├── config/
    │   └── repo-configs/   # Per-repo orchestration config
    ├── .gitignore
    └── README.md
    ```
  - Each agent directory gets the standard structure: `IDENTITY.md`, `SOUL.md`, `AGENTS.md`, `SECURITY.md`, `CONTEXT.md`, `USER.md`, `TOOLS.md`, `RETENTION.md`, `PLAYBOOK.md`, `CONVENTIONS.md`, `MEMORY.md`, `HEARTBEAT.md`, `skills/`, `memory/`
  - Create `.gitignore` (ignore .env, node_modules, state/*.json)
  - Create README.md explaining the defizoo-brain purpose and relationship to brain-core

  **Must NOT do**:
  - Do NOT populate agent files yet (Tasks 11-13 handle that)
  - Do NOT copy content from brains-old blindly
  - Do NOT create build/deploy infrastructure (that's brain-core's job)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 5 (after Phase 1)
  - **Blocks**: Tasks 11-14
  - **Blocked By**: Task 9

  **References**:
  - `brains-old/defizoo-brain/` — Old structure as reference (NOT to copy blindly)
  - `template/` — brain-core template for agent brain file structure
  - `skills/core/create-agent/SKILL.md` — Defines the expected agent directory layout

  **Acceptance Criteria**:
  - [ ] `ls defizoo-brain/agents/` → apeai, gregailia, carpincho, carl
  - [ ] `ls defizoo-brain/knowledge/` → defizoo, team, apeguru, discord
  - [ ] `ls defizoo-brain/extensions/` → discord-roles, telegramuser
  - [ ] Each agent dir has at minimum: IDENTITY.md, SOUL.md, AGENTS.md, skills/, memory/
  - [ ] `test -f defizoo-brain/.gitignore` → exists
  - [ ] `test -f defizoo-brain/README.md` → exists

  **Commit**: YES
  - Message: `feat: scaffold defizoo-brain repository structure`
  - Files: `defizoo-brain/`

---

- [x] 11. Curate Agent Identities

  **What to do**:
  - For each agent, review old identity files and create fresh, curated versions:
  - **ApeAI** (OpenClaw orchestrator):
    - Source: `brains-old/defizoo-brain/agents/apeai/IDENTITY.md`, `SOUL.md`
    - Role: Creates, updates, manages other agents. Head of AI.
    - Skills: create-agent, manage-agent, upgrade-agent, memory-brain, proactive-agent-behavior
  - **GregAIlia** (HR / Head of Staff):
    - Source: `brains-old/defizoo-brain/agents/gregailia/IDENTITY.md`, `SOUL.md`, `knowledge/team/hr-playbook.md`
    - Role: HR, team coordination, birthday tracking, engagement
    - Skills: memory-brain, proactive-agent-behavior
  - **Carpincho** (Coding guru):
    - Source: `brains-old/crapincho-brain/IDENTITY.md`, `SOUL.md`
    - Role: Coding orchestration, OpenCode sessions, code review
    - Skills: coding-orchestrator, code-review-orchestrator, memory-brain, proactive-agent-behavior
  - **Carl** (Sales & BD):
    - Source: `brains-old/defizoo-brain/agents/sales/IDENTITY.md`, `SOUL.md`
    - Role: Sales, business development, partnerships
    - Skills: memory-brain, proactive-agent-behavior
  - For each agent: IDENTITY.md, SOUL.md, USER.md, AGENTS.md, SECURITY.md, CONTEXT.md, TOOLS.md, RETENTION.md, PLAYBOOK.md, CONVENTIONS.md, MEMORY.md (empty), HEARTBEAT.md
  - Remove accumulated cruft, org-specific references that don't belong, outdated context

  **Must NOT do**:
  - Do NOT invent new personality traits — preserve character from old brains
  - Do NOT copy memory files (those are ephemeral)
  - Do NOT change security model — preserve admin verification from old brains

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 12, 13, 14)
  - **Blocks**: None
  - **Blocked By**: Task 10

  **References**:
  - `brains-old/defizoo-brain/agents/apeai/IDENTITY.md` — ApeAI source identity
  - `brains-old/defizoo-brain/agents/gregailia/IDENTITY.md` — GregAIlia source identity
  - `brains-old/crapincho-brain/IDENTITY.md` — Carpincho source identity (146 lines)
  - `brains-old/crapincho-brain/SOUL.md` — Carpincho source soul (102 lines)
  - `brains-old/defizoo-brain/agents/sales/IDENTITY.md` — Carl/Sales source identity
  - `brains-old/crapincho-brain/AGENTS.md` — Carpincho session protocol (best example)
  - `brains-old/crapincho-brain/SECURITY.md` — Carpincho security model (most comprehensive, 152 lines)
  - `template/` — brain-core template for default file structure

  **WHY Each Reference Matters**:
  - Each source identity file preserves the character and personality that should be carried forward
  - Carpincho's AGENTS.md and SECURITY.md are the most mature versions — use as base for all agents

  **Acceptance Criteria**:
  - [ ] Each of 4 agents has IDENTITY.md with ≥ 20 lines of curated content
  - [ ] Each agent has SOUL.md with ≥ 10 lines
  - [ ] Each agent has AGENTS.md, SECURITY.md, USER.md, CONTEXT.md, TOOLS.md
  - [ ] `grep -r "GregAIlia" defizoo-brain/agents/carpincho/` → 0 (no cross-agent contamination)
  - [ ] `grep -r "carpincho" defizoo-brain/agents/gregailia/` → 0 (no cross-agent contamination)

  **Commit**: YES
  - Message: `feat: curate agent identities for ApeAI, GregAIlia, Carpincho, and Carl`
  - Files: `defizoo-brain/agents/*/`

---

- [x] 12. Curate Shared Knowledge Base

  **What to do**:
  - Copy and curate knowledge from `brains-old/defizoo-brain/knowledge/`:
    - `knowledge/defizoo/` — org-structure.md, culture.md, vaultedge.md, felines.md, apebond.md
    - `knowledge/team/` — roster.md, profiles.md, hr-playbook.md, birthdays.md, policies.md
    - `knowledge/apeguru/` — personal-os.md, identity.md, writing-voice.md
    - `knowledge/discord/` — engagement.md, roster-ids.md
  - Review each file for:
    - Outdated information (pre-restructure)
    - Duplicate content across files
    - Sensitive information (tokens, IDs — redact if found)
  - Create `knowledge/agents/registry.md` with table header for the 4 new agents

  **Must NOT do**:
  - Do NOT rewrite knowledge content — only remove obviously outdated sections
  - Do NOT merge files — keep the existing organization

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 11, 13, 14)
  - **Blocks**: None
  - **Blocked By**: Task 10

  **References**:
  - `brains-old/defizoo-brain/knowledge/` — All 19 knowledge files (1,134 lines total)
  - `brains-old/gregailia-brain/knowledge/` — Earlier versions (for cross-reference)

  **Acceptance Criteria**:
  - [ ] `ls defizoo-brain/knowledge/defizoo/ defizoo-brain/knowledge/team/ defizoo-brain/knowledge/apeguru/ defizoo-brain/knowledge/discord/` → all directories with content
  - [ ] `wc -l defizoo-brain/knowledge/defizoo/*.md | tail -1` → ≥ 300 lines total
  - [ ] `grep -rE "ghp_|gho_|sk-|token:" defizoo-brain/knowledge/` → 0 matches (no secrets)
  - [ ] `test -f defizoo-brain/knowledge/agents/registry.md` → exists

  **Commit**: YES
  - Message: `feat: curate shared knowledge base for defizoo-brain`
  - Files: `defizoo-brain/knowledge/`

---

- [x] 13. Agent Skills Selection and Config

  **What to do**:
  - For each agent, populate `skills/` directory with the appropriate skills (copied from brain-core):
    - **ApeAI**: create-agent, manage-agent, upgrade-agent, memory-brain, proactive-agent-behavior
    - **GregAIlia**: memory-brain, proactive-agent-behavior
    - **Carpincho**: coding-orchestrator, code-review-orchestrator, memory-brain, proactive-agent-behavior
    - **Carl**: memory-brain, proactive-agent-behavior
  - Create `brain.yaml` for each agent with:
    - Agent ID, name, description
    - Deployment mode (sandbox/main)
    - Memory backend selection
    - MCP server selection
    - Skills list
  - Set up Carpincho-specific workspace config:
    - `config/repo-configs/` — Copy from `brains-old/crapincho-brain/repo-configs/`
    - `config/templates/` — plan-prompt.md, fix-prompt.md templates
    - `state/` directory with .gitkeep (not committed, created at runtime)

  **Must NOT do**:
  - Do NOT modify copied skill files — they come from brain-core as-is
  - Do NOT create new skills

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 11, 12, 14)
  - **Blocks**: None
  - **Blocked By**: Task 10

  **References**:
  - `skills/core/` — Operational skills for ApeAI
  - `skills/behavioral/` — Behavioral skills for all agents
  - `skills/specialized/` — Specialized skills for Carpincho
  - `brains-old/crapincho-brain/repo-configs/chainpilot-monorepo.json` — Example repo config
  - `template/brain.yaml` — brain.yaml template

  **Acceptance Criteria**:
  - [ ] `ls defizoo-brain/agents/apeai/skills/` → create-agent, manage-agent, upgrade-agent, memory-brain, proactive-agent-behavior
  - [ ] `ls defizoo-brain/agents/carpincho/skills/` → coding-orchestrator, code-review-orchestrator, memory-brain, proactive-agent-behavior
  - [ ] `ls defizoo-brain/agents/gregailia/skills/` → memory-brain, proactive-agent-behavior
  - [ ] `ls defizoo-brain/agents/carl/skills/` → memory-brain, proactive-agent-behavior
  - [ ] Each agent has brain.yaml with agent_id, name, skills list
  - [ ] `test -d defizoo-brain/agents/carpincho/config/repo-configs` → exists

  **Commit**: YES
  - Message: `feat: configure agent skills and brain.yaml for all 4 agents`
  - Files: `defizoo-brain/agents/*/skills/`, `defizoo-brain/agents/*/brain.yaml`

---

- [x] 14. Extensions Setup

  **What to do**:
  - Copy `brains-old/gregailia-brain/.openclaw/extensions/discord-roles/` → `defizoo-brain/extensions/discord-roles/`
  - Copy `brains-old/defizoo-brain/.openclaw/extensions/telegramuser/` → `defizoo-brain/extensions/telegramuser/`
  - Review for hardcoded values, secrets, or outdated references
  - Create `defizoo-brain/extensions/README.md` explaining each extension

  **Must NOT do**:
  - Do NOT modify extension logic
  - Do NOT add new extensions
  - Do NOT include node_modules (add to .gitignore)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 11, 12, 13)
  - **Blocks**: None
  - **Blocked By**: Task 10

  **References**:
  - `brains-old/gregailia-brain/.openclaw/extensions/discord-roles/` — Discord role management (14K, TypeScript)
  - `brains-old/defizoo-brain/.openclaw/extensions/telegramuser/` — Telegram integration (48K, TypeScript with tests)

  **Acceptance Criteria**:
  - [ ] `ls defizoo-brain/extensions/discord-roles/` → index.ts, openclaw.plugin.json
  - [ ] `ls defizoo-brain/extensions/telegramuser/src/` → TypeScript source files
  - [ ] `test -f defizoo-brain/extensions/README.md` → exists
  - [ ] `grep -r "ghp_\|gho_\|sk-\|token:" defizoo-brain/extensions/ --include="*.ts" --include="*.json"` → 0 matches

  **Commit**: YES
  - Message: `feat: set up discord-roles and telegramuser extensions for defizoo-brain`
  - Files: `defizoo-brain/extensions/`

---

## Commit Strategy

| After Task | Message | Key Files |
|------------|---------|-----------|
| 1 | `refactor: restructure skills to three-tier architecture` | skills/ |
| 2 | `chore: trim template — remove unused, move OpenClaw-specific` | template/, docs/openclaw/ |
| 3 | `docs: add orchestration scripts path resolution spec` | docs/orchestration-scripts.md |
| 4 | `feat: extract and generalize orchestration scripts` | scripts/orchestration/ |
| 5 | `feat: extract Discord pipe integration` | integrations/ |
| 6 | `docs: extract orchestration documentation` | docs/orchestration/ |
| 7 | `feat: add scripts and integrations to Docker image` | docker/Dockerfile |
| 8 | `fix: update skill references for new structure` | skills/ |
| 9 | `docs: update README for new capabilities` | README.md |
| 10 | `feat: scaffold defizoo-brain structure` | defizoo-brain/ |
| 11 | `feat: curate 4 agent identities` | defizoo-brain/agents/ |
| 12 | `feat: curate shared knowledge base` | defizoo-brain/knowledge/ |
| 13 | `feat: configure agent skills and brain.yaml` | defizoo-brain/agents/ |
| 14 | `feat: set up extensions` | defizoo-brain/extensions/ |

---

## Success Criteria

### Phase 1: brain-core Finalization
```bash
# Skills three-tier
ls skills/core/ skills/behavioral/ skills/specialized/  # All 3 tiers exist
find skills/ -name "SKILL.md" | wc -l  # Expected: 7

# Template trimmed
test ! -f template/LEARNINGS.md  # Removed
test -f docs/openclaw/BOOT.md    # Moved

# Scripts extracted
ls scripts/orchestration/*.sh | wc -l  # Expected: ≥ 14
grep -r "carpincho" scripts/orchestration/ | grep -v test  # Expected: 0 matches

# Docker builds
docker buildx build --platform linux/amd64 --target gateway -f docker/Dockerfile .  # Expected: exit 0
```

### Phase 2: defizoo-brain Preparation
```bash
# Structure
ls defizoo-brain/agents/  # apeai, gregailia, carpincho, carl
ls defizoo-brain/knowledge/  # defizoo, team, apeguru, discord

# Agent completeness
for agent in apeai gregailia carpincho carl; do
  test -f defizoo-brain/agents/$agent/IDENTITY.md || echo "MISSING: $agent/IDENTITY.md"
  test -f defizoo-brain/agents/$agent/brain.yaml || echo "MISSING: $agent/brain.yaml"
  test -d defizoo-brain/agents/$agent/skills/ || echo "MISSING: $agent/skills/"
done

# No secrets
grep -rE "ghp_|gho_|sk-|xoxb-" defizoo-brain/ --include="*.md" --include="*.json" --include="*.ts"  # Expected: 0 matches
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] Docker image builds
- [ ] No secrets in repository
- [ ] All 14 tasks complete
