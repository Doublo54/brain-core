# Fix Sandbox Browser + Enable MCP Servers for Sandboxed Agents

## TL;DR

> **Quick Summary**: Revert the bridge server patch that broke native browser auth for sandboxed agents, and enable Playwright + Puppeteer MCP servers inside sandbox containers by fixing the mcporter config's npm cache paths.
>
> **Deliverables**:
> - Native OpenClaw browser working for all 7 sandboxed agents (no more "Unauthorized")
> - Playwright MCP (22 tools) available to all 7 sandboxed agents via mcporter
> - Puppeteer MCP available to all 7 sandboxed agents via mcporter
>
> **Estimated Effort**: Short
> **Parallel Execution**: YES — 2 waves
> **Critical Path**: Task 1 (brain-core) and Task 2 (defizoo-brain) are independent → Task 3 (restart + verify)

---

## Context

### Original Request
Fix sandbox browser "Unauthorized" errors and enable Playwright MCP + Puppeteer MCP + native browser for all sandboxed agents.

### Interview Summary
**Key Discussions**:
- User reported Aria and Hatzo get "Unauthorized" when using browser tool
- User reported Hatzo says "No MCP servers configured"
- User wants all three browser automation approaches available

**Research Findings**:
- **Browser 401 root cause**: Our entrypoint patch (step 9) changes bridge baseUrl from `http://127.0.0.1:{port}` to `http://172.17.0.1:{port}`. The auth function `withLoopbackBrowserAuth` ONLY adds auth headers for loopback URLs — non-loopback URLs skip auth entirely. The patch was unnecessary because the browser tool executes on the gateway (ACP CLI has zero browser references), and `network_mode: host` already makes loopback work.
- **MCP root cause**: mcporter IS available in sandbox and DOES discover `./config/mcporter.json` from CWD=/workspace. But npx fails because `/tmp` is `noexec` and `/home/node` is read-only. Setting `NPM_CONFIG_CACHE=/workspace/.npm-cache` in the mcporter.json `env` field fixes this — confirmed with 22 healthy Playwright tools.
- **Puppeteer MCP**: `@hisma/server-puppeteer@0.6.5` (maintained fork of deprecated official package) works in sandbox with `PUPPETEER_SKIP_DOWNLOAD=true` and `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium`.

### Metis Review
**Identified Gaps** (addressed):
- Puppeteer needs `PUPPETEER_SKIP_DOWNLOAD=true` and `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium` to prevent Chromium download crash → added to env
- Puppeteer needs separate user-data-dir to avoid profile conflicts with Playwright → configured as `/workspace/.puppeteer-profile`
- Live `openclaw.json` doesn't auto-update from template → not needed for this fix (entrypoint change applies on every boot, mcporter.json changes are in workspace files)
- Version pinning concern (`@latest` vs pinned) → deferred, separate concern

---

## Work Objectives

### Core Objective
Restore native browser functionality for sandboxed agents by reverting the broken bridge patch, and enable Playwright + Puppeteer MCP tools by fixing npm cache paths in per-agent mcporter configs.

### Concrete Deliverables
- `brain-core/docker/entrypoint.sh` — step 9 removed (lines 243-276)
- 7 × `defizoo-brain/agents/*/config/mcporter.json` — updated with env vars + puppeteer entry

### Definition of Done
- [ ] `docker logs <gateway> | grep "Unauthorized"` shows zero new 401 errors after restart
- [ ] `docker exec <any-sandbox> mcporter list` shows 2 healthy servers (playwright + puppeteer)
- [ ] Sandboxed agent successfully navigates a URL via native browser tool (via Discord)

### Must Have
- Native browser tool working for sandboxed agents (no 401)
- Playwright MCP available (22 tools, healthy)
- Puppeteer MCP available (healthy)

### Must NOT Have (Guardrails)
- `allowHostControl: true` anywhere
- Changes to `brain-core/config/mcporter.json` (gateway-level, separate concern)
- Changes to `defizoo-brain/config/openclaw.json.template`
- Changes to Dockerfile, docker-compose files, or sandbox-browser-entrypoint.sh
- New mcporter.json files for non-sandboxed agents (main, apeai)
- Changes to `boulder.json`
- Direct merges to main

---

## Verification Strategy (MANDATORY)

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
> ALL verification is executed by the agent using tools.

### Test Decision
- **Infrastructure exists**: NO (no unit test framework for shell scripts / JSON configs)
- **Automated tests**: NO
- **Framework**: N/A

### Agent-Executed QA Scenarios (MANDATORY)

Verification via bash commands inside Docker containers. All scenarios run post-deployment (after `make down && make up`).

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — independent repos):
├── Task 1: Remove bridge patch from entrypoint.sh (brain-core)
└── Task 2: Update 7 mcporter.json files (defizoo-brain)

Wave 2 (After Wave 1):
└── Task 3: Restart gateway + verify everything works
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 3 | 2 |
| 2 | None | 3 | 1 |
| 3 | 1, 2 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 2 | task(category="quick", load_skills=[], run_in_background=false) × 2 |
| 2 | 3 | task(category="quick", load_skills=[], run_in_background=false) |

---

## TODOs

- [ ] 1. Remove bridge server patch from entrypoint.sh

  **What to do**:
  - Delete lines 243–276 of `brain-core/docker/entrypoint.sh` (the entire step 9 block)
  - This includes the comment header, the SANDBOX_BUNDLE detection, the node -e script, and the closing `fi`
  - Renumber step 10 comment to step 9 (lines 278-286 become the new step 9)
  - Update the file header comment (lines 5-13) to remove reference to step 9 and adjust step numbering

  **Must NOT do**:
  - Do NOT touch steps 1–8 or step 10 (gateway exec)
  - Do NOT modify `sandbox-browser-entrypoint.sh`
  - Do NOT modify any docker-compose files
  - Do NOT touch the Dockerfile

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
    - No special skills needed — simple file edit
  - **Skills Evaluated but Omitted**:
    - `git-master`: Not needed for the edit itself, commit handled separately

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `brain-core/docker/entrypoint.sh:243-276` — The step 9 block to DELETE entirely. Contains the bridge patch that breaks browser auth.
  - `brain-core/docker/entrypoint.sh:278-286` — Step 10 (gateway exec) that should be renumbered to step 9.
  - `brain-core/docker/entrypoint.sh:5-13` — File header listing all steps. Remove the old step 9 line and renumber.

  **Why Each Reference Matters**:
  - Lines 243-276: This is THE code causing the 401. It patches the sandbox bundle to change `127.0.0.1` to `0.0.0.0` in bind and `172.17.0.1` in baseUrl. The `withLoopbackBrowserAuth` function skips auth for non-loopback URLs, causing every sandbox browser request to get 401'd.
  - Lines 278-286: After removing step 9, this becomes the last step. Renumber for consistency.
  - Lines 5-13: Header comments enumerate all steps. Must stay accurate.

  **Acceptance Criteria**:

  - [ ] `grep -c 'bridge server must bind to loopback' brain-core/docker/entrypoint.sh` → 0 (patch code removed)
  - [ ] `grep -c '0\.0\.0\.0' brain-core/docker/entrypoint.sh` → 0 (no 0.0.0.0 references)
  - [ ] `grep -c '172.17.0.1' brain-core/docker/entrypoint.sh` → 0 (no bridge IP references)
  - [ ] `grep -c 'SANDBOX_BUNDLE' brain-core/docker/entrypoint.sh` → 0 (variable removed)
  - [ ] The file has a clean step 1-9 numbering (was 1-10, now 1-9 after removing old step 9)
  - [ ] `sh -n brain-core/docker/entrypoint.sh` → exit 0 (valid shell syntax)

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Entrypoint has no bridge patch code
    Tool: Bash
    Preconditions: Edit completed
    Steps:
      1. grep -c 'Sandbox browser bridge patch' brain-core/docker/entrypoint.sh
      2. Assert: output is "0"
      3. grep -c 'SANDBOX_BUNDLE' brain-core/docker/entrypoint.sh
      4. Assert: output is "0"
      5. wc -l < brain-core/docker/entrypoint.sh
      6. Assert: line count is approximately 253 (was 287, removed ~34 lines)
      7. sh -n brain-core/docker/entrypoint.sh
      8. Assert: exit code 0
    Expected Result: All bridge patch references removed, valid shell
    Evidence: Command output captured

  Scenario: Step numbering is consistent
    Tool: Bash
    Preconditions: Edit completed
    Steps:
      1. grep -n '# [0-9]*\.' brain-core/docker/entrypoint.sh
      2. Assert: Steps numbered 1 through 9 (previously 1 through 10)
      3. Assert: No gaps in numbering
      4. head -15 brain-core/docker/entrypoint.sh
      5. Assert: Header comment lists steps 1-9
    Expected Result: Clean sequential numbering
    Evidence: grep output captured
  ```

  **Commit**: YES
  - Message: `fix(entrypoint): remove bridge server patch that broke sandbox browser auth`
  - Files: `docker/entrypoint.sh`
  - Pre-commit: `sh -n docker/entrypoint.sh`

---

- [ ] 2. Update per-agent mcporter.json with env vars and Puppeteer MCP

  **What to do**:
  - Update all 7 per-agent `config/mcporter.json` files with:
    1. Add `env` block to existing `playwright` entry: `NPM_CONFIG_CACHE=/workspace/.npm-cache` and `HOME=/workspace`
    2. Add new `puppeteer` entry with `@hisma/server-puppeteer@0.6.5`
  - All 7 files should be identical (they currently are)
  - The target content for each file:

  ```json
  {
    "mcpServers": {
      "playwright": {
        "command": "/opt/mise/shims/npx",
        "args": [
          "-y",
          "@playwright/mcp@latest",
          "--headless",
          "--no-sandbox",
          "--executable-path=/usr/bin/chromium",
          "--user-data-dir=/workspace/.playwright-profile",
          "--output-dir=/workspace/playwright-output"
        ],
        "env": {
          "NPM_CONFIG_CACHE": "/workspace/.npm-cache",
          "HOME": "/workspace"
        }
      },
      "puppeteer": {
        "command": "/opt/mise/shims/npx",
        "args": [
          "-y",
          "@hisma/server-puppeteer@0.6.5"
        ],
        "env": {
          "NPM_CONFIG_CACHE": "/workspace/.npm-cache",
          "HOME": "/workspace",
          "PUPPETEER_SKIP_DOWNLOAD": "true",
          "PUPPETEER_EXECUTABLE_PATH": "/usr/bin/chromium",
          "PUPPETEER_USER_DATA_DIR": "/workspace/.puppeteer-profile"
        }
      }
    },
    "imports": []
  }
  ```

  **Must NOT do**:
  - Do NOT touch `brain-core/config/mcporter.json` (gateway config)
  - Do NOT add mcporter.json to non-sandboxed agents (main, apeai)
  - Do NOT change `defizoo-brain/config/openclaw.json.template`
  - Do NOT add any new files — only edit existing 7 files

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
    - Simple JSON file updates across 7 files
  - **Skills Evaluated but Omitted**:
    - `git-master`: Not needed for the edit itself

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `defizoo-brain/agents/hatzo/config/mcporter.json` — Current file (playwright only, no env). All 7 are identical.
  - `brain-core/config/mcporter.json:42-47` — Gateway's playwright config for comparison (uses `npx` directly, no env needed since gateway HOME is writable)

  **External References**:
  - `@playwright/mcp` — Playwright MCP server npm package. Provides 22 browser automation tools.
  - `@hisma/server-puppeteer@0.6.5` — Maintained fork of deprecated `@modelcontextprotocol/server-puppeteer`. Provides Puppeteer-based browser automation.

  **WHY Each Reference Matters**:
  - Per-agent mcporter.json: Shows exact current content to know what to change
  - Gateway mcporter.json: Shows the pattern for env vars in mcporter server configs (the `env` field is supported and used by other servers like zai-vision)
  - The env vars are critical: without `NPM_CONFIG_CACHE=/workspace/.npm-cache`, npx fails with ENOENT because `/home/node/.npm/_cacache` is read-only. Without `PUPPETEER_SKIP_DOWNLOAD=true`, Puppeteer crashes trying to download Chromium.

  **File Paths** (all 7):
  - `defizoo-brain/agents/carl/config/mcporter.json`
  - `defizoo-brain/agents/carpincho/config/mcporter.json`
  - `defizoo-brain/agents/finance/config/mcporter.json`
  - `defizoo-brain/agents/gregailia/config/mcporter.json`
  - `defizoo-brain/agents/hatzo/config/mcporter.json`
  - `defizoo-brain/agents/marketing/config/mcporter.json`
  - `defizoo-brain/agents/miro/config/mcporter.json`

  **Acceptance Criteria**:

  - [ ] All 7 files contain valid JSON: `for f in defizoo-brain/agents/*/config/mcporter.json; do jq . "$f" > /dev/null; done` → exit 0
  - [ ] All 7 files are identical: `md5sum defizoo-brain/agents/*/config/mcporter.json | awk '{print $1}' | sort -u | wc -l` → 1
  - [ ] Each file has exactly 2 MCP servers: `jq '.mcpServers | keys | length' defizoo-brain/agents/hatzo/config/mcporter.json` → 2
  - [ ] Playwright has env.NPM_CONFIG_CACHE: `jq '.mcpServers.playwright.env.NPM_CONFIG_CACHE' defizoo-brain/agents/hatzo/config/mcporter.json` → "/workspace/.npm-cache"
  - [ ] Puppeteer has PUPPETEER_SKIP_DOWNLOAD: `jq '.mcpServers.puppeteer.env.PUPPETEER_SKIP_DOWNLOAD' defizoo-brain/agents/hatzo/config/mcporter.json` → "true"
  - [ ] Puppeteer has PUPPETEER_EXECUTABLE_PATH: `jq '.mcpServers.puppeteer.env.PUPPETEER_EXECUTABLE_PATH' defizoo-brain/agents/hatzo/config/mcporter.json` → "/usr/bin/chromium"

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: All 7 mcporter.json files are valid and identical
    Tool: Bash
    Preconditions: Edits completed
    Steps:
      1. for f in defizoo-brain/agents/*/config/mcporter.json; do jq . "$f" > /dev/null || echo "INVALID: $f"; done
      2. Assert: No "INVALID" output
      3. md5sum defizoo-brain/agents/*/config/mcporter.json
      4. Assert: All 7 checksums are identical
      5. jq '.mcpServers | keys' defizoo-brain/agents/hatzo/config/mcporter.json
      6. Assert: ["playwright", "puppeteer"]
    Expected Result: 7 identical valid JSON files, each with 2 MCP servers
    Evidence: Command output captured

  Scenario: Puppeteer env prevents Chromium download
    Tool: Bash
    Preconditions: Files updated
    Steps:
      1. jq -r '.mcpServers.puppeteer.env.PUPPETEER_SKIP_DOWNLOAD' defizoo-brain/agents/hatzo/config/mcporter.json
      2. Assert: "true"
      3. jq -r '.mcpServers.puppeteer.env.PUPPETEER_EXECUTABLE_PATH' defizoo-brain/agents/hatzo/config/mcporter.json
      4. Assert: "/usr/bin/chromium"
    Expected Result: Puppeteer configured to use system Chromium
    Evidence: jq output captured
  ```

  **Commit**: YES
  - Message: `feat(agents): add MCP env config and Puppeteer MCP server for sandbox agents`
  - Files: `agents/*/config/mcporter.json` (7 files)
  - Pre-commit: `for f in agents/*/config/mcporter.json; do jq . "$f" > /dev/null; done`

---

- [ ] 3. Restart gateway and verify all three browser capabilities

  **What to do**:
  - Run `make down && make up` from `brain-core/` root to restart with the new entrypoint (without bridge patch)
  - Wait for gateway to become healthy
  - Verify native browser tool works (no 401)
  - Verify Playwright MCP is healthy inside sandbox
  - Verify Puppeteer MCP is healthy inside sandbox

  **Must NOT do**:
  - Do NOT delete the live `openclaw.json` (template changes from bind mount removal were cosmetic and the live config works fine)
  - Do NOT modify any files — this is verification only

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: Not needed — we're testing via CLI, not browser automation

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (sequential, after Tasks 1 & 2)
  - **Blocks**: None (final task)
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `brain-core/Makefile` — Contains `make up` and `make down` targets
  - `brain-core/docker/docker-compose.dev.yml` — Dev compose file used by `make up`

  **Acceptance Criteria**:

  - [ ] Gateway container is healthy: `docker ps --format "{{.Names}} {{.Status}}" | grep openclaw` shows "healthy"
  - [ ] No bridge patch applied: `docker exec <gateway> grep -c '0\.0\.0\.0' /app/dist/sandbox-*.js 2>/dev/null` — output should show the ORIGINAL count (patch not applied)
  - [ ] Browser service ready: gateway logs show `[browser/service] Browser control service ready`
  - [ ] No 401 errors in gateway logs (after restart): `docker logs <gateway> 2>&1 | grep -c "Unauthorized"` → 0
  - [ ] Sandbox containers spawn: `docker ps --format "{{.Names}}" | grep sbx-agent` shows sandbox containers
  - [ ] mcporter in sandbox shows 2 healthy servers: `docker exec <sandbox> mcporter list 2>&1 | grep -c 'healthy'` → 2
  - [ ] Playwright has 22 tools: `docker exec <sandbox> mcporter list 2>&1 | grep 'playwright'` shows tool count
  - [ ] Puppeteer is healthy: `docker exec <sandbox> mcporter list 2>&1 | grep 'puppeteer'` shows healthy status

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Gateway restarts clean without bridge patch
    Tool: Bash
    Preconditions: Tasks 1 and 2 committed, working dir is brain-core/
    Steps:
      1. make down (timeout: 30s)
      2. make up (timeout: 120s)
      3. Wait 30s for gateway to become healthy
      4. docker ps --format "{{.Names}} {{.Status}}" | grep openclaw
      5. Assert: Status contains "healthy"
      6. docker logs $(docker ps -qf name=openclaw) 2>&1 | grep "Sandbox browser bridge patched"
      7. Assert: NO output (patch no longer applied)
      8. docker logs $(docker ps -qf name=openclaw) 2>&1 | grep "Browser control service ready"
      9. Assert: Output found (browser service started)
    Expected Result: Clean startup, no bridge patch, browser service ready
    Evidence: Docker logs captured

  Scenario: Native browser tool works for sandboxed agent (no 401)
    Tool: Bash
    Preconditions: Gateway running and healthy, at least one sandbox agent active
    Steps:
      1. Wait for sandbox containers: docker ps --format "{{.Names}}" | grep sbx-agent (timeout: 60s)
      2. Trigger browser tool usage on a sandboxed agent (via Discord DM to Aria or Hatzo: "navigate to https://example.com")
      3. Monitor gateway logs: docker logs -f $(docker ps -qf name=openclaw) 2>&1 | grep -E "browser|401|Unauthorized" (timeout: 30s)
      4. Assert: Logs show successful browser.request (✓), NOT "Unauthorized"
    Expected Result: Browser tool succeeds, returns page content
    Evidence: Gateway log output captured
    Note: This scenario requires user to send a Discord message — mark as MANUAL VERIFICATION REQUIRED

  Scenario: Playwright MCP healthy inside sandbox
    Tool: Bash
    Preconditions: Sandbox container running with updated mcporter.json
    Steps:
      1. SANDBOX=$(docker ps --format "{{.Names}}" | grep sbx-agent | head -1)
      2. docker exec $SANDBOX mcporter list 2>&1
      3. Assert: Output contains "playwright" with "healthy" status
      4. Assert: Output shows tool count (22 tools expected)
      5. docker exec $SANDBOX sh -c 'echo "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}" | NPM_CONFIG_CACHE=/workspace/.npm-cache HOME=/workspace timeout 15 npx -y @playwright/mcp@latest --headless --no-sandbox --executable-path=/usr/bin/chromium 2>/dev/null'
      6. Assert: JSON response contains "serverInfo.name": "Playwright"
    Expected Result: Playwright MCP responds with 22 tools
    Evidence: mcporter list output + MCP init response captured

  Scenario: Puppeteer MCP healthy inside sandbox
    Tool: Bash
    Preconditions: Sandbox container running with updated mcporter.json
    Steps:
      1. SANDBOX=$(docker ps --format "{{.Names}}" | grep sbx-agent | head -1)
      2. docker exec $SANDBOX mcporter list 2>&1
      3. Assert: Output contains "puppeteer" with "healthy" status
      4. docker exec $SANDBOX sh -c 'echo "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}" | NPM_CONFIG_CACHE=/workspace/.npm-cache HOME=/workspace PUPPETEER_SKIP_DOWNLOAD=true PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium timeout 15 npx -y @hisma/server-puppeteer@0.6.5 2>/dev/null'
      5. Assert: JSON response contains "serverInfo.name": "hisma/server-puppeteer"
    Expected Result: Puppeteer MCP responds with tools
    Evidence: mcporter list output + MCP init response captured

  Scenario: No Puppeteer Chromium download attempted
    Tool: Bash
    Preconditions: Puppeteer MCP tested at least once
    Steps:
      1. SANDBOX=$(docker ps --format "{{.Names}}" | grep sbx-agent | head -1)
      2. docker exec $SANDBOX ls -la /workspace/.cache/puppeteer/ 2>&1
      3. Assert: Directory doesn't exist OR is empty (no downloaded Chromium)
      4. docker exec $SANDBOX du -sh /workspace/.npm-cache/ 2>/dev/null
      5. Assert: Size is reasonable (< 200MB)
    Expected Result: System Chromium used, no redundant download
    Evidence: ls output captured
  ```

  **Commit**: NO (verification only, no file changes)

---

## Commit Strategy

| After Task | Repo | Message | Files | Verification |
|------------|------|---------|-------|--------------|
| 1 | brain-core | `fix(entrypoint): remove bridge server patch that broke sandbox browser auth` | `docker/entrypoint.sh` | `sh -n docker/entrypoint.sh` |
| 2 | defizoo-brain | `feat(agents): add MCP env config and Puppeteer MCP server for sandbox agents` | `agents/*/config/mcporter.json` (7 files) | `jq . agents/*/config/mcporter.json` |
| 3 | — | No commit (verification only) | — | — |

**PR Strategy**:
- brain-core: Push to `staging`, PR to `main`
- defizoo-brain: Push to `staging`, PR to `main`
- Both PRs can be created in parallel after Wave 1

---

## Success Criteria

### Verification Commands
```bash
# 1. No bridge patch in entrypoint
grep -c 'SANDBOX_BUNDLE' brain-core/docker/entrypoint.sh
# Expected: 0

# 2. mcporter shows 2 healthy servers in sandbox
docker exec $(docker ps --format "{{.Names}}" | grep sbx-agent | head -1) mcporter list
# Expected: playwright (22 tools, healthy) + puppeteer (N tools, healthy)

# 3. No 401 in gateway logs after restart
docker logs $(docker ps -qf name=openclaw) 2>&1 | grep -c "Unauthorized"
# Expected: 0

# 4. Browser control service ready
docker logs $(docker ps -qf name=openclaw) 2>&1 | grep "Browser control service ready"
# Expected: Found
```

### Final Checklist
- [ ] Native browser tool works for sandboxed agents (no 401 Unauthorized)
- [ ] Playwright MCP healthy with 22 tools in all sandbox containers
- [ ] Puppeteer MCP healthy in all sandbox containers
- [ ] No bridge patch code in entrypoint.sh
- [ ] No Puppeteer Chromium downloads in sandbox (uses system Chromium)
- [ ] Non-sandboxed agents (main, apeai) unaffected — gateway browser still works
- [ ] All 7 mcporter.json files identical and valid JSON
