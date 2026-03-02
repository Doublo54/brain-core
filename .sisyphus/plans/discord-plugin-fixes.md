# Discord User Plugin: Fix All Review Findings & E2E Test

## TL;DR

> **Quick Summary**: Fix all 14 code review findings (2 critical, 5 warning, 7 info) in the Discord user plugin, then E2E test the complete DM → agent → response flow with a real Discord user token.
>
> **Deliverables**:
> - All 14 review issues resolved in `plugins/discorduser/`
> - Plugin loads, connects, and responds to DMs end-to-end
> - All 5 CI checks pass
> - Clean commit on `feat/discorduser` branch ready for PR
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Task 1 (critical fixes) → Task 5 (adapter hardening) → Task 8 (E2E test)

---

## Context

### Original Request
Fix all 14 issues found during deep code review of the Discord user plugin (compared against the battle-tested Telegram user plugin), then E2E test with a real Discord user token.

### Interview Summary
**Key Discussions**:
- User wants ALL 14 issues fixed (not just critical/warning)
- User has a `DISCORD_USER_TOKEN` ready for testing
- Working in `brain-core-discord` worktree on `feat/discorduser` branch
- Telegramuser plugin is the reference implementation (already E2E verified on `main`)

**Research Findings**:
- Discord adapter has internal `READY_TIMEOUT_MS=30s` in `waitForReady()`, but `channel.ts` `startAccount` doesn't wrap connect() with an outer timeout for the full login+ready sequence
- DUB `client.close()` is synchronous — safe to call without await, but better to wrap for consistency
- Discord typing endpoint is `POST /channels/{id}/typing` — DUB exposes it via `client.fetch_request()` raw API
- Discord `allowFrom` IDs are numeric snowflake strings — Zod schema currently only accepts `z.string()` but should also accept `z.number()` for flexibility
- Telegramuser dock sets `outbound: { textChunkLimit: 3500 }` — Discord needs equivalent with 2000 char limit

### Metis Review
**Identified Gaps** (addressed):
- Typing indicator implementation must use raw Discord API (`POST /channels/{id}/typing`) since DUB has no built-in method
- Connect timeout should wrap the FULL `adapter.connect()` call (login + ready), not duplicate the internal ready timeout
- Dock registration is more than cosmetic — it tells OpenClaw the text chunk limit and capabilities
- Audit account (#13) should be minimal — just log a warning, don't fail startup

---

## Work Objectives

### Core Objective
Make the Discord user plugin production-ready by fixing all identified code review issues and verifying end-to-end functionality.

### Concrete Deliverables
- Fixed `plugins/discorduser/src/discord-adapter.ts` — typing indicators, disconnect fix, bigint handling
- Fixed `plugins/discorduser/src/channel.ts` — disconnect ordering, connect timeout, dock registration
- Fixed `plugins/discorduser/src/monitor.ts` — self-filter optimization, approval logging
- Fixed `plugins/discorduser/src/send.ts` — consolidated retry logic, flood wait extraction
- Fixed `plugins/discorduser/src/media.ts` — temp directory cleanup
- Fixed `plugins/discorduser/src/userbot-config-schema.ts` — allowFrom accepts strings and numbers
- Fixed `plugins/discorduser/src/userbot-accounts.ts` — allowFrom type alignment
- Fixed `plugins/discorduser/index.ts` — dock registration
- Updated `plugins/discorduser/USERBOT-README.md` — multi-account env var limitation
- E2E verified: DM → agent processes → response auto-sent back

### Definition of Done
- [ ] All 14 review findings addressed with code changes
- [ ] `make test && make test-approval` passes (68/68 tests)
- [ ] All 5 CI checks pass (genericization, compose, shell, docker builds)
- [ ] E2E: Send DM to bot account → receive agent response back
- [ ] Clean commit on `feat/discorduser` branch

### Must Have
- Typing indicators during agent processing
- Correct disconnect ordering (disconnect BEFORE deleting session)
- Connect timeout at gateway level (prevent infinite hang)
- Dock registration with 2000 char text limit
- Self-message filtering using `isSelfMessage()` method
- Config schema accepting both string and number IDs

### Must NOT Have (Guardrails)
- NO changes to `plugins/telegramuser/` — it's stable and tested
- NO changes to files outside `plugins/discorduser/`, `docker/`, `config/`, `.env.example`
- NO refactoring of the DUB library itself — work around its limitations
- NO new npm dependencies — use existing DUB API surface
- NO changes to OpenClaw SDK types or plugin-sdk
- NO business-specific strings (defizoo, carpincho, etc.) — CI will catch these
- NO changes to `brain-core/brains-old/`

---

## Verification Strategy (MANDATORY)

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION — with one exception**
>
> Tasks 1–7 MUST be verifiable WITHOUT any human action.
> **Task 8 (E2E test) is the explicit exception**: it requires the user to send a DM from a separate Discord account.
> This is unavoidable because: (1) we only have one Discord user token, (2) generating inbound DMs
> requires a second Discord identity, and (3) automating a second Discord user account adds
> unnecessary complexity and risk (ToS, token management).
>
> **Task 8 protocol**: The agent handles startup, log monitoring, and verification.
> The user provides the single manual action: sending a DM from their other Discord account.

### Test Decision
- **Infrastructure exists**: YES (bun test, 68 tests on main)
- **Automated tests**: Tests-after (verify CI remains green; no new unit tests for these fixes since they're behavioral/integration-level)
- **Framework**: bun test (existing)

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

**Verification Tool by Deliverable Type:**

| Type | Tool | How Agent Verifies |
|------|------|-------------------|
| Code fixes | Bash (TypeScript compilation) | `bun build` or `tsc --noEmit` on extensions/discord |
| CI checks | Bash (make targets) | `make test`, CI scripts |
| E2E flow | Bash (docker logs) + manual token test | `make up`, check logs, send DM |
| Config validation | Bash (jq/cat) | Inspect generated openclaw.json |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — independent fixes):
├── Task 1: Critical fixes (typing + disconnect ordering)
├── Task 2: Config schema + accounts type fix
└── Task 3: Media cleanup + README docs

Wave 2 (After Wave 1 — depends on adapter changes):
├── Task 4: Monitor hardening (self-filter, approval logging)
├── Task 5: Adapter hardening (connect timeout, retry consolidation, flood wait)
└── Task 6: Dock registration + index.ts update

Wave 3 (After Wave 2 — integration verification):
├── Task 7: CI verification (all 5 checks + tests)
└── Task 8: E2E test with real Discord token

Critical Path: Task 1 → Task 5 → Task 8
Parallel Speedup: ~35% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 4, 5, 6 | 2, 3 |
| 2 | None | 4 | 1, 3 |
| 3 | None | 7 | 1, 2 |
| 4 | 1, 2 | 7 | 5, 6 |
| 5 | 1 | 7, 8 | 4, 6 |
| 6 | 1 | 7 | 4, 5 |
| 7 | 3, 4, 5, 6 | 8 | None |
| 8 | 7 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 2, 3 | task(category="deep", load_skills=[], run_in_background=false) per task |
| 2 | 4, 5, 6 | task(category="deep", load_skills=[], run_in_background=false) per task |
| 3 | 7, 8 | task(category="unspecified-high", load_skills=[], run_in_background=false) |

---

## TODOs

- [ ] 1. CRITICAL: Add typing indicators + fix disconnect ordering

  **What to do**:

  **1a. Add `setTyping()` to DiscordAdapter** (`discord-adapter.ts`):
  - Add method `async setTyping(channelId: string): Promise<void>` to the `DiscordAdapter` class
  - Implementation: Use DUB's raw request API to POST to Discord's typing endpoint
    ```typescript
    async setTyping(channelId: string): Promise<void> {
      try {
        await this.client.fetch_request(`/channels/${channelId}/typing`, { method: "POST" });
      } catch {
        // Best-effort — typing indicators are non-critical
      }
    }
    ```
  - This matches Telegram's pattern of best-effort typing with silent catch (see `user-adapter.ts:120-131`)

  **1b. Call `setTyping()` before dispatch in monitor.ts** (`monitor.ts`):
  - Before the `dispatchReplyWithBufferedBlockDispatcher` call at line 187, add:
    ```typescript
    // Show typing indicator while agent processes
    adapter.setTyping(channelId).catch(() => {});
    ```
  - Place it after the route/envelope resolution (around line 176) but before the dispatch call

  **1c. Fix disconnect ordering in channel.ts** (`channel.ts:243-248`):
  - Current (WRONG): `activeSessions.delete(accountId)` → `adapter.disconnect()`
  - Fixed (RIGHT): `adapter.disconnect()` → `activeSessions.delete(accountId)`
  - Change `disconnectSession()` to:
    ```typescript
    async function disconnectSession(accountId: string): Promise<void> {
      const session = activeSessions.get(accountId);
      if (!session) return;
      await session.adapter.disconnect().catch(() => undefined);
      activeSessions.delete(accountId);
    }
    ```

  **Must NOT do**:
  - Do NOT add typing to guild/channel messages — only DMs
  - Do NOT make typing failure throw — it must be best-effort
  - Do NOT change the disconnect method itself — only the ordering in `disconnectSession()`

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Touches 3 files with interconnected logic; needs careful understanding of adapter lifecycle
  - **Skills**: []
    - No special skills needed — pure TypeScript editing
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: Not frontend work
    - `git-master`: No git operations in this task

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Tasks 4, 5, 6
  - **Blocked By**: None (can start immediately)

  **References** (CRITICAL):

  **Pattern References** (existing code to follow):
  - `plugins/telegramuser/src/user-adapter.ts:120-131` — Telegram's `setTyping()` implementation: best-effort pattern with silent catch, uses `getInputEntity()` then `invoke(SetTyping)`. Discord equivalent is simpler (raw HTTP POST).
  - `plugins/telegramuser/src/channel.ts:988-991` — Telegram disconnect ordering: `removeInbound()` → `activeAccounts.delete()` → `disconnectAdapter()`. This is the CORRECT order to follow.

  **API/Type References** (contracts to implement against):
  - `plugins/discorduser/src/discord-adapter.ts:131-133` — Existing `rawRequest()` method that wraps `client.fetch_request()` — use this for typing endpoint
  - `plugins/discorduser/src/discord-adapter.ts:62-68` — Current `disconnect()` method — note it's synchronous (`client.close()`) but wrapped in async

  **Documentation References**:
  - Discord API docs: `POST /channels/{channel.id}/typing` triggers typing indicator for 10 seconds

  **WHY Each Reference Matters**:
  - `user-adapter.ts:120-131`: Shows the exact pattern to replicate — best-effort, silent catch, non-blocking
  - `channel.ts:988-991`: Demonstrates the CORRECT disconnect ordering that was already battle-tested in Telegram
  - `discord-adapter.ts:131-133`: Shows existing raw API access — reuse this pattern for typing

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: setTyping method exists and is callable
    Tool: Bash
    Preconditions: plugins/discorduser/ code is saved
    Steps:
      1. grep -n "setTyping" plugins/discorduser/src/discord-adapter.ts
      2. Assert: Method definition found (async setTyping(channelId: string))
      3. grep -n "setTyping" plugins/discorduser/src/monitor.ts
      4. Assert: Call to adapter.setTyping found before dispatchReply
    Expected Result: setTyping defined in adapter and called in monitor
    Evidence: grep output captured

  Scenario: Disconnect ordering is correct
    Tool: Bash
    Preconditions: channel.ts is saved
    Steps:
      1. grep -A5 "async function disconnectSession" plugins/discorduser/src/channel.ts
      2. Assert: adapter.disconnect() appears BEFORE activeSessions.delete()
    Expected Result: Disconnect before delete
    Evidence: grep output captured
  ```

  **Evidence to Capture:**
  - [ ] grep output showing setTyping in adapter and monitor
  - [ ] grep output showing correct disconnect ordering

  **Commit**: YES (groups with Tasks 2, 3)
  - Message: `fix(discord): add typing indicators, fix disconnect ordering, harden adapter`
  - Files: `plugins/discorduser/src/discord-adapter.ts`, `plugins/discorduser/src/channel.ts`, `plugins/discorduser/src/monitor.ts`

---

- [ ] 2. Fix config schema + accounts type alignment

  **What to do**:

  **2a. Update allowFrom schema** (`userbot-config-schema.ts:31`):
  - Change: `allowFrom: z.array(z.string()).optional()`
  - To: `allowFrom: z.array(z.union([z.string(), z.number()])).optional()`
  - This matches Telegram's pattern at `telegramuser/src/channel.ts:45`

  **2b. Update allowFrom type in accounts** (`userbot-accounts.ts:9`):
  - Change: `allowFrom?: string[]`
  - To: `allowFrom?: (string | number)[]`
  - Update `normalizeAllowEntries` in `monitor.ts:309-316` to handle numbers:
    - Current: `entries.map((entry) => String(entry).trim().toLowerCase())`
    - Already handles it since `String(number)` works — but update the function signature to accept `(string | number)[]`

  **2c. Add bigint safety to adapter** (`discord-adapter.ts`):
  - Add bigint handling to `asString()` function (line 270):
    ```typescript
    function asString(value: unknown): string | null {
      if (typeof value === "bigint") {
        return String(value);
      }
      if (typeof value !== "string") {
        return null;
      }
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }
    ```
  - Also add bigint handling to `asString()` in `monitor.ts:345-351` (same fix)
  - This is the EXACT pattern that fixed GramJS bigint issues (see `user-adapter.ts:59-64`)

  **Must NOT do**:
  - Do NOT change the runtime behavior of `normalizeAllowEntries` — it already calls `String()` which handles numbers
  - Do NOT add bigint to `asNumber()` — numbers in Discord are always regular numbers, not bigints

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small schema changes across 3 files, clear pattern to follow
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: Task 4
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `plugins/telegramuser/src/channel.ts:45` — Telegram's allowFrom schema: `z.union([z.string(), z.number()])` — exact pattern to replicate
  - `plugins/telegramuser/src/user-adapter.ts:59-64` — Telegram's bigint→string conversion in `valueToString()` — the fix we applied for GramJS

  **API/Type References**:
  - `plugins/discorduser/src/userbot-config-schema.ts:31` — Current schema: `z.array(z.string())` — needs to become `z.array(z.union([z.string(), z.number()]))`
  - `plugins/discorduser/src/userbot-accounts.ts:9` — TypeScript type `allowFrom?: string[]` — needs `(string | number)[]`

  **Acceptance Criteria**:

  ```
  Scenario: Config schema accepts numbers in allowFrom
    Tool: Bash
    Steps:
      1. grep "allowFrom" plugins/discorduser/src/userbot-config-schema.ts
      2. Assert: z.union([z.string(), z.number()]) present
      3. grep "allowFrom" plugins/discorduser/src/userbot-accounts.ts
      4. Assert: (string | number)[] type present
    Expected Result: Both string and number types accepted

  Scenario: bigint safety in asString
    Tool: Bash
    Steps:
      1. grep -A3 "function asString" plugins/discorduser/src/discord-adapter.ts
      2. Assert: "bigint" check present
      3. grep -A3 "function asString" plugins/discorduser/src/monitor.ts
      4. Assert: "bigint" check present
    Expected Result: Both asString functions handle bigint
  ```

  **Commit**: YES (groups with Tasks 1, 3)
  - Files: `plugins/discorduser/src/userbot-config-schema.ts`, `plugins/discorduser/src/userbot-accounts.ts`, `plugins/discorduser/src/discord-adapter.ts`, `plugins/discorduser/src/monitor.ts`

---

- [ ] 3. Fix media cleanup + update docs

  **What to do**:

  **3a. Fix temp directory cleanup** (`media.ts:63-69`):
  - Current `cleanupTempFile()` only deletes the file, leaving the parent `mkdtempSync` directory orphaned
  - Update to also remove the parent directory:
    ```typescript
    import { mkdtempSync, unlinkSync, rmdirSync, writeFileSync } from "node:fs";
    import { dirname } from "node:path";

    export async function cleanupTempFile(path: string): Promise<void> {
      try {
        unlinkSync(path);
        // Also remove the temp directory created by mkdtempSync
        const dir = dirname(path);
        if (dir.includes("discorduser-media-")) {
          rmdirSync(dir);
        }
      } catch (err) {
        console.error(`[discorduser] failed to cleanup temp file ${path}: ${String(err)}`);
      }
    }
    ```

  **3b. Document multi-account env var limitation** (`USERBOT-README.md`):
  - Add a section noting that `DISCORD_USER_TOKEN` env var only works for the default account
  - Multi-account setups must configure tokens directly in `openclaw.json`

  **Must NOT do**:
  - Do NOT change the `downloadToTemp()` function — only the cleanup
  - Do NOT use `fs.promises.rm` with `recursive` — too aggressive; use `rmdirSync` which only removes empty dirs

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small file fix + docs update, trivial changes
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Task 7
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `plugins/discorduser/src/media.ts:32` — `mkdtempSync(join(tmpdir(), "discorduser-media-"))` creates the directory
  - `plugins/discorduser/src/media.ts:63-69` — Current `cleanupTempFile()` only unlinks the file

  **Acceptance Criteria**:

  ```
  Scenario: Cleanup removes both file and directory
    Tool: Bash
    Steps:
      1. grep -n "rmdirSync\|dirname" plugins/discorduser/src/media.ts
      2. Assert: Both rmdirSync and dirname imported and used
      3. grep "discorduser-media-" plugins/discorduser/src/media.ts
      4. Assert: Guard check for temp dir name before rmdir
    Expected Result: Cleanup function removes file AND parent temp directory

  Scenario: README documents multi-account limitation
    Tool: Bash
    Steps:
      1. grep -i "multi.*account\|env.*var.*only\|default.*account" plugins/discorduser/USERBOT-README.md
      2. Assert: Documentation about env var limitation exists
    Expected Result: Multi-account env var limitation documented
  ```

  **Commit**: YES (groups with Tasks 1, 2)
  - Files: `plugins/discorduser/src/media.ts`, `plugins/discorduser/USERBOT-README.md`

---

- [ ] 4. Monitor hardening: self-filter optimization + approval logging

  **What to do**:

  **4a. Use `isSelfMessage()` instead of direct comparison** (`monitor.ts:36`):
  - Current: `if (message.author.id === adapter.self().id) return;`
  - Change to: `if (adapter.isSelfMessage(message)) return;`
  - This uses the adapter's own method (already defined at `discord-adapter.ts:135-137`) and avoids calling `adapter.self()` on every message
  - Also remove the `const selfId = adapter.self().id;` from line 29 since it's no longer needed for filtering (but keep it for `mentionGateRegex` — actually, cache it as `const selfId = adapter.self().id` stays for the regex, so just change line 36)

  **4b. Add logging for approval notification failure** (`channel.ts:649-661`):
  - Current `notifyApproval` silently returns if session not found
  - Add a console.warn when session is null:
    ```typescript
    notifyApproval: async ({ id, accountId, cfg }: any) => {
      const targetId = normalizeAllowEntry(String(id));
      const session = resolveSessionForAccount({
        accountId: typeof accountId === "string" ? accountId : null,
        cfg: (cfg ?? undefined) as OpenClawConfig | undefined,
      });
      if (!session) {
        console.warn(`[discorduser] notifyApproval: no active session for account ${accountId ?? "default"}, cannot notify user ${targetId}`);
        return;
      }
      // ... rest unchanged
    }
    ```

  **Must NOT do**:
  - Do NOT remove `selfId` variable entirely — it's used for `mentionGateRegex` on line 30
  - Do NOT make approval notification throw — just log and return

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two small targeted changes in monitor.ts and channel.ts
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `plugins/discorduser/src/discord-adapter.ts:135-137` — Existing `isSelfMessage()` method to use
  - `plugins/discorduser/src/monitor.ts:29` — `selfId` still needed for regex, just don't use it for filtering
  - `plugins/discorduser/src/monitor.ts:36` — Current self-filter line to change

  **Acceptance Criteria**:

  ```
  Scenario: Self-message filtering uses isSelfMessage
    Tool: Bash
    Steps:
      1. grep "isSelfMessage" plugins/discorduser/src/monitor.ts
      2. Assert: adapter.isSelfMessage(message) call present
      3. grep -c "adapter.self().id" plugins/discorduser/src/monitor.ts
      4. Assert: Only appears once (for selfId used in regex, not in filter)
    Expected Result: Self-filter uses adapter method

  Scenario: Approval notification logs on missing session
    Tool: Bash
    Steps:
      1. grep -A2 "if (!session)" plugins/discorduser/src/channel.ts | grep -i "warn\|log"
      2. Assert: console.warn present for missing session case
    Expected Result: Warning logged when no session for approval
  ```

  **Commit**: YES (groups with Tasks 5, 6)
  - Files: `plugins/discorduser/src/monitor.ts`, `plugins/discorduser/src/channel.ts`

---

- [ ] 5. Adapter hardening: connect timeout, consolidated retry, flood wait extraction

  **What to do**:

  **5a. Add connect timeout in gateway.startAccount** (`channel.ts:581-582`):
  - Current: `const self = await adapter.connect(token);` (no timeout)
  - Wrap with timeout pattern from Telegram (`telegramuser/src/channel.ts:163-189`):
    ```typescript
    const CONNECT_TIMEOUT_MS = 30_000;
    let timedOut = false;
    let timeoutTimer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timeoutTimer = setTimeout(() => {
        timedOut = true;
        reject(new Error(`[discorduser] ${account.accountId}: connect timed out after ${CONNECT_TIMEOUT_MS}ms`));
      }, CONNECT_TIMEOUT_MS);
    });
    let self: DiscordUserInfo;
    try {
      self = await Promise.race([adapter.connect(token), timeout]);
    } catch (err) {
      if (timedOut) {
        adapter.disconnect().catch(() => {});
      }
      throw err;
    } finally {
      clearTimeout(timeoutTimer);
    }
    ```
  - Note: The adapter has its own internal `READY_TIMEOUT_MS=30s`, but this outer timeout covers the FULL `login()` + `waitForReady()` sequence. The adapter's internal timeout only covers the ready wait.

  **5b. Remove adapter-level retry from sendText/sendFile** (`discord-adapter.ts:70-91`):
  - Current: `sendText()` and `sendFile()` use `withRateLimitRetry()` AND `send.ts` has `sendChunkWithRetry()`
  - This creates compounding retries (3 × 3 = 9 attempts max)
  - **Decision**: Keep rate-limit retry ONLY in the adapter (it knows about 429 responses). Remove transient retry from `send.ts` — OR — remove adapter retry and keep send retry.
  - **Recommended**: Keep adapter-level rate limit retry (it parses Discord-specific 429 errors). Modify `send.ts` to NOT retry on rate-limit errors (only retry on transient network errors). Add a check in `isTransientSendError` to exclude 429:
    ```typescript
    export function isTransientSendError(err: unknown): boolean {
      const msg = String((err as { message?: string })?.message ?? err).toLowerCase();
      // Don't retry rate limits here — adapter handles those
      if (msg.includes("429") || msg.includes("rate limit")) return false;
      return (
        msg.includes("timeout") ||
        msg.includes("temporar") ||
        msg.includes("network") ||
        msg.includes("connection") ||
        msg.includes("econnreset") ||
        msg.includes("eai_again") ||
        msg.includes("fetch failed")
      );
    }
    ```

  **5c. Extract retry_after from 429 errors in send.ts** (`send.ts`):
  - Actually, since we're keeping rate limit in the adapter and excluding from send.ts, this is handled. The adapter already parses `retry_after` at `discord-adapter.ts:241`. No additional extraction needed in send.ts.

  **Must NOT do**:
  - Do NOT remove `withRateLimitRetry()` from the adapter — it's the correct place for 429 handling
  - Do NOT add a second timeout inside `connect()` — the adapter already has one for ready
  - Do NOT change the adapter's `READY_TIMEOUT_MS` constant

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Touches retry logic across two files, needs careful understanding of error flow
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: Tasks 7, 8
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `plugins/telegramuser/src/channel.ts:163-189` — Telegram's connect timeout pattern: Promise.race with cleanup on timeout. COPY THIS PATTERN.
  - `plugins/discorduser/src/discord-adapter.ts:194-211` — Adapter's `withRateLimitRetry()` — KEEP this, it correctly parses 429
  - `plugins/discorduser/src/send.ts:89-117` — Send-level retry — MODIFY to exclude rate-limit errors

  **API/Type References**:
  - `plugins/discorduser/src/discord-adapter.ts:50-60` — `connect()` method: login + waitForReady + refreshSelfInfo
  - `plugins/discorduser/src/discord-adapter.ts:13-16` — `DiscordUserInfo` return type from connect

  **Acceptance Criteria**:

  ```
  Scenario: Connect timeout wraps adapter.connect()
    Tool: Bash
    Steps:
      1. grep -n "CONNECT_TIMEOUT_MS\|Promise.race\|timedOut" plugins/discorduser/src/channel.ts
      2. Assert: CONNECT_TIMEOUT_MS defined, Promise.race used, timedOut flag present
      3. grep "adapter.disconnect" plugins/discorduser/src/channel.ts | grep "timedOut"
      4. Assert: Cleanup on timeout present
    Expected Result: Connect wrapped with 30s timeout and cleanup

  Scenario: Rate limit excluded from transient retry
    Tool: Bash
    Steps:
      1. grep -B2 -A10 "isTransientSendError" plugins/discorduser/src/send.ts
      2. Assert: 429 or rate limit check returns false early
    Expected Result: send.ts doesn't retry rate-limited requests (adapter handles those)
  ```

  **Commit**: YES (groups with Tasks 4, 6)
  - Message: `fix(discord): add connect timeout, consolidate retry logic, filter self-messages`
  - Files: `plugins/discorduser/src/channel.ts`, `plugins/discorduser/src/send.ts`

---

- [ ] 6. Add dock registration + minimal audit

  **What to do**:

  **6a. Create DiscordUserDock** (`channel.ts`):
  - Add a `discordUserDock` export, following Telegram's pattern at `telegramuser/src/channel.ts:441-458`
  - Discord's text limit is 2000 (from `send.ts:5`)
  - Structure:
    ```typescript
    export const discordUserDock: ChannelDock = {
      id: "discorduser",
      capabilities: {
        chatTypes: ["direct", "guild"],
        media: true,
        blockStreaming: true,
      },
      outbound: { textChunkLimit: 2000 },
      config: {
        resolveAllowFrom: ({ cfg, accountId }) =>
          (resolveDiscordUserAccount({ cfg, accountId }).config.allowFrom ?? []).map((entry) => String(entry)),
        formatAllowFrom: ({ allowFrom }) =>
          allowFrom
            .map((entry) => String(entry).trim().toLowerCase())
            .filter(Boolean)
            .map((entry) => entry.replace(/^(discorduser|discord|user):/i, "")),
      },
    };
    ```
  - Import `ChannelDock` from `openclaw/plugin-sdk`

  **6b. Register dock in index.ts** (`index.ts:45`):
  - Change: `api.registerChannel({ plugin: discordUserPlugin });`
  - To: `api.registerChannel({ plugin: discordUserPlugin, dock: discordUserDock });`
  - Add import: `import { discordUserPlugin, discordUserDock, sendDiscordUserApprovalText } from "./src/channel.js";`

  **6c. Add minimal audit account** (`channel.ts`):
  - Add `auditAccount` to the plugin object, after `notifyApproval`:
    ```typescript
    auditAccount: async ({ account, cfg }: any) => {
      // Minimal audit: just check if token is configured
      const resolved = resolveDiscordUserAccount({ cfg, accountId: account.accountId });
      if (!resolved.token) {
        return { ok: false, message: "No token configured" };
      }
      return { ok: true };
    },
    ```
  - This is intentionally minimal — full guild membership checks are future work

  **Must NOT do**:
  - Do NOT add guild membership verification to audit — just token check
  - Do NOT add groups config to the dock — Discord guilds work differently from Telegram groups
  - Do NOT change any existing plugin methods

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Needs to understand OpenClaw SDK's ChannelDock/ChannelPlugin interfaces and how Telegram registers
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Task 7
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `plugins/telegramuser/src/channel.ts:441-458` — Telegram's dock: `id`, `capabilities`, `outbound.textChunkLimit`, `config.resolveAllowFrom`, `config.formatAllowFrom`. REPLICATE this structure.
  - `plugins/telegramuser/index.ts:17` — `api.registerChannel({ plugin: telegramUserPlugin, dock: telegramUserDock })` — registration pattern

  **API/Type References**:
  - `plugins/discorduser/src/send.ts:5` — `DISCORD_TEXT_LIMIT = 2000` — use this for `textChunkLimit`
  - `plugins/discorduser/src/channel.ts:4-14` — Existing imports from `openclaw/plugin-sdk` — add `ChannelDock`
  - `plugins/discorduser/src/userbot-accounts.ts:64` — `resolveDiscordUserAccount()` — use in dock's `resolveAllowFrom`

  **Acceptance Criteria**:

  ```
  Scenario: Dock registered with correct chunk limit
    Tool: Bash
    Steps:
      1. grep "discordUserDock" plugins/discorduser/src/channel.ts
      2. Assert: Export exists with textChunkLimit: 2000
      3. grep "dock:" plugins/discorduser/index.ts
      4. Assert: dock: discordUserDock registered
    Expected Result: Dock registered with 2000 char limit

  Scenario: Audit account exists and checks token
    Tool: Bash
    Steps:
      1. grep "auditAccount" plugins/discorduser/src/channel.ts
      2. Assert: auditAccount method exists in plugin
    Expected Result: Minimal audit method present
  ```

  **Commit**: YES (groups with Tasks 4, 5)
  - Files: `plugins/discorduser/src/channel.ts`, `plugins/discorduser/index.ts`

---

- [ ] 7. CI verification: all tests and checks pass

  **What to do**:
  - Run all CI checks from the `brain-core-discord` worktree
  - Run: `make test` (55 orchestrator tests)
  - Run: `make test-approval` (13 approval gate tests)
  - Run all 5 CI checks:
    1. Genericization check (no business-specific strings)
    2. Compose validation (`docker compose config`)
    3. Shell syntax (`shellcheck`)
    4. Docker build (brain-core)
    5. Docker build (brain)
  - Fix any failures

  **Must NOT do**:
  - Do NOT skip any CI check
  - Do NOT modify test files to make tests pass — fix the source code
  - Do NOT add `defizoo`, `carpincho`, or other business strings in fixes

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Needs to run multiple CI checks, potentially fix issues across files
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (sequential)
  - **Blocks**: Task 8
  - **Blocked By**: Tasks 3, 4, 5, 6

  **References**:

  **Pattern References**:
  - `.github/workflows/ci.yml` — CI workflow defining all 5 checks
  - `Makefile` — `test` and `test-approval` targets

  **Acceptance Criteria**:

  ```
  Scenario: All tests pass
    Tool: Bash
    Preconditions: All code fixes applied
    Steps:
      1. Run: make test
      2. Assert: 55/55 pass, exit code 0
      3. Run: make test-approval
      4. Assert: 13/13 pass, exit code 0
    Expected Result: 68/68 tests pass
    Evidence: Test output captured

  Scenario: CI checks pass
    Tool: Bash
    Steps:
      1. Run each CI check script
      2. Assert: All 5 checks exit 0
    Expected Result: All CI green
    Evidence: Check output captured
  ```

  **Commit**: NO (only if fixes needed; otherwise Task 8 handles final commit)

---

- [ ] 8. E2E test: real Discord DM → agent response

  > **MANUAL EXCEPTION**: This task involves ONE manual user action (sending a DM from a separate
  > Discord account). This is the only task in the plan that requires human involvement.
  > All other verification steps (startup, log monitoring, commit) are agent-executed.
  >
  > **Why manual is necessary**: Automating inbound DMs would require a second Discord user token
  > and a scripted sender, adding ToS risk and unnecessary complexity for a one-time verification.

  **What to do**:

  **8a. Set up environment** (agent-executed):
  - Ensure `DISCORD_USER_TOKEN` is set in `.env` file in the brain-core worktree
  - Run `make clean` (wipe volumes for fresh config template)
  - Run `make up` (start the full stack)
  - Wait for logs to show discorduser plugin loaded and connected

  **8b. Verify plugin startup** (agent-executed):
  - Check `make logs` for:
    - `[discorduser] connected as <username>` — adapter connected
    - No errors related to discorduser in startup logs
  - Check config was generated: `make shell` then `cat /data/openclaw.json | jq '.channels.discorduser'`

  **8c. Send test DM** (USER ACTION REQUIRED):
  - Prompt the user: "Plugin is connected. Please send a DM from your other Discord account to the user account. Message: 'Hello, who are you?'"
  - Wait for user confirmation that DM was sent

  **8d. Verify response flow** (agent-executed):
  - Monitor `make logs` for:
    - Inbound message received (sender ID visible)
    - Policy check passed (sender in allowlist)
    - Typing indicator attempted (no error logged)
    - Agent model called (kimi-coding/k2p5)
    - Response auto-sent back
  - Ask user to confirm response appeared in Discord DM

  **8e. Commit all changes** (agent-executed):
  - Stage all modified files in `plugins/discorduser/`
  - Create commit with descriptive message
  - Push to `feat/discorduser` branch

  **Must NOT do**:
  - Do NOT use the same Discord account as both sender and receiver
  - Do NOT skip the `make clean` step — stale volumes will have old config
  - Do NOT commit the `.env` file

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Requires Docker orchestration, log monitoring, and understanding of the full gateway flow
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (after Task 7)
  - **Blocks**: None (final task)
  - **Blocked By**: Task 7

  **References**:

  **Pattern References**:
  - Telegramuser E2E test flow from prior session — same pattern: start stack, check logs, send message, verify response

  **Documentation References**:
  - `.env.example` — Documents all required env vars including `DISCORD_USER_TOKEN`
  - `docker/docker-compose.dev.yml` — Dev compose with discorduser volume mount

  **Acceptance Criteria**:

  ```
  Scenario: Plugin starts and connects successfully (agent-executed)
    Tool: Bash
    Preconditions: DISCORD_USER_TOKEN in .env, make clean done
    Steps:
      1. Run: make up (in background or detached)
      2. Wait for: "connected as" in logs (timeout: 60s)
      3. Run: make logs | grep -i "discorduser"
      4. Assert: "connected as <username>" present
      5. Assert: No error lines for discorduser
    Expected Result: Plugin loaded and connected
    Evidence: Log output captured to .sisyphus/evidence/task-8-startup.log

  Scenario: DM triggers agent response (requires user action for DM send)
    Tool: Bash (log monitoring) + user action
    Preconditions: Plugin connected
    Steps:
      1. Agent prompts user: "Send a DM to the user account from your other Discord account"
      2. Agent waits for user confirmation that DM was sent
      3. Agent monitors logs: make logs --follow | grep -i "discorduser\|inbound\|dispatch"
      4. Assert: Inbound log line with sender ID appears (timeout: 30s)
      5. Assert: Agent model invocation logged (kimi-coding or similar)
      6. Assert: Outbound/send log line appears
      7. Agent asks user: "Did you receive a response in Discord?"
    Expected Result: Full round-trip confirmed via logs + user confirmation
    Evidence: Log output captured to .sisyphus/evidence/task-8-e2e.log

  Scenario: Typing indicator not erroring (agent-executed)
    Tool: Bash (log monitoring)
    Preconditions: DM processed (from previous scenario)
    Steps:
      1. grep -i "typing.*error\|error.*typing\|setTyping.*fail" in captured logs
      2. Assert: No typing-related errors found (empty grep result is success)
    Expected Result: Typing indicator attempted without error
    Evidence: grep output captured
  ```

  **Evidence to Capture:**
  - [ ] Startup logs showing successful connection
  - [ ] Inbound message log showing DM received
  - [ ] Agent response log showing model invocation
  - [ ] Outbound message log showing reply sent

  **Commit**: YES
  - Message: `fix(discord): address all 14 review findings, E2E verified`
  - Files: All modified files in `plugins/discorduser/`, `docker/`, `config/`
  - Pre-commit: `make test && make test-approval`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1+2+3 | `fix(discord): add typing indicators, fix disconnect ordering, schema/cleanup/docs` | discord-adapter.ts, channel.ts, monitor.ts, schema.ts, accounts.ts, media.ts, README | grep assertions |
| 4+5+6 | `fix(discord): connect timeout, retry consolidation, dock registration, monitor hardening` | channel.ts, send.ts, monitor.ts, index.ts | grep assertions |
| 8 | `fix(discord): all 14 review findings addressed, E2E verified` | All above + any CI fixes | make test + make test-approval |

---

## Success Criteria

### Verification Commands
```bash
# All tests pass
make test           # Expected: 55/55 pass
make test-approval  # Expected: 13/13 pass

# Plugin connects
make logs | grep "connected as"  # Expected: discorduser username

# No errors
make logs | grep -i "error.*discorduser"  # Expected: empty (no errors)
```

### Final Checklist
- [ ] All 14 review findings addressed
- [ ] Typing indicators implemented (setTyping in adapter, called in monitor)
- [ ] Disconnect ordering fixed (disconnect before delete)
- [ ] Connect timeout at gateway level (30s)
- [ ] Retry logic consolidated (no compounding)
- [ ] Config schema accepts string and number IDs
- [ ] Bigint safety in asString functions
- [ ] Dock registered with 2000 char limit
- [ ] Self-message filtering uses isSelfMessage()
- [ ] Approval notification logs on failure
- [ ] Media cleanup removes temp directory
- [ ] README documents env var limitation
- [ ] Minimal audit account
- [ ] E2E: DM → agent → response verified
- [ ] All "Must NOT Have" guardrails respected
- [ ] All tests pass (68/68)
- [ ] All 5 CI checks pass
