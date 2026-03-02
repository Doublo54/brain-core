# TelegramUser Plugin — MTProto/GramJS

Standalone `telegramuser` channel plugin. Replaces the bot-API telegram plugin with personal-account transport via GramJS, reusing the same ChannelPlugin routing/policy pipeline.

## Branch model

- `telegramplugin` — original bot plugin fork (baseline)
- `feat/usertelegram` — user-account refactor (this branch)

Diff: `git diff telegramplugin..feat/usertelegram`

## Setup

### 1. Get Telegram API credentials

1. Go to https://my.telegram.org/apps and create an app
2. Note your **API ID** (number) and **API Hash** (string)

### 2. Generate a StringSession

```bash
make down                  # stop the stack first — session can only be used by one process
make telegram-session      # interactive: phone → OTP → 2FA → outputs session string
```

Copy the three values into `.env`:
```
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=abc123...
TELEGRAM_STRING_SESSION=1BQA...
```

### 3. Start the stack

```bash
make clean && make up      # clean required on first setup (generates fresh config)
make logs                  # look for: [telegramuser:default] connected as @YourUsername
```

> **IMPORTANT**: Each StringSession can only be used by ONE process. Do NOT run the
> generator, a test script, or any other GramJS client while the stack is up — this
> causes `AUTH_KEY_DUPLICATED` and permanently invalidates the session.

## Config

Under `channels.telegramuser` in `openclaw.json`:

```json
{
  "channels": {
    "telegramuser": {
      "enabled": true,
      "apiId": 12345678,
      "apiHash": "your_api_hash",
      "stringSession": "your_string_session",
      "dmPolicy": "pairing",
      "allowFrom": ["123456789"]
    }
  }
}
```

### Multi-account

```json
{
  "channels": {
    "telegramuser": {
      "enabled": true,
      "defaultAccount": "sales",
      "accounts": {
        "sales": {
          "apiId": 12345678,
          "apiHash": "abc",
          "stringSession": "...",
          "dmPolicy": "allowlist",
          "allowFrom": ["111222333"]
        }
      }
    }
  }
}
```

### DM policy

| Policy | Behavior |
|--------|----------|
| `pairing` (default) | Unknown senders get pairing code; approved pass through |
| `allowlist` | Only `allowFrom` entries; others silently dropped |
| `open` | All DMs accepted |
| `disabled` | All DMs dropped |

`allowFrom` normalized: `tgu:123` -> `123`, case-insensitive. Config + pairing store merged at runtime.

## Parity with canonical bot plugin

| Feature | Bot plugin | telegramuser | Notes |
|---------|-----------|-------------|-------|
| DM inbound/outbound | ✅ | ✅ | Full text support with chunking + retry |
| DM policy (pairing/allowlist/open/disabled) | ✅ | ✅ | Same semantics, config + pairing store merged |
| Multi-account | ✅ | ✅ | `accounts.*` overlay on base config |
| Rate limiting | ✅ | ✅ | Per-chat send chain with `minIntervalSeconds` |
| Text chunking | ✅ | ✅ | Smart split at newline/space boundaries |
| Flood wait handling | ✅ | ✅ | Parses `FLOOD_WAIT_N`, exponential backoff on transient errors |
| Approval queue (auto/manual/auto-allowlist) | ✅ | ✅ | Inline in deliver callback with draft persistence |
| Draft persistence (file-based) | ✅ | ✅ | `drafts.ts` — atomic JSON file store with expiry, maxPendingDrafts cap |
| Draft queue overflow protection | ✅ | ✅ | Drops + notifies operator when `maxPendingDrafts` reached |
| Config schema (zod) | ✅ | ✅ | `buildChannelConfigSchema` wrapping |
| Agent routing | ✅ | ✅ | `resolveAgentRoute` with peer kind=direct |
| Inbound context (Body/RawBody/SessionKey/etc.) | ✅ | ✅ | `finalizeInboundContext` with all standard fields |
| Reply prefix options | ✅ | ✅ | `createReplyPrefixOptions` with onModelSelected |
| Account enable/disable/delete | ✅ | ✅ | SDK helpers (`setAccountEnabledInConfigSection`, etc.) |
| Pairing notify | ✅ | ✅ | Sends approval confirmation via `sendUserMessage` |
| Security warnings (groupPolicy=open) | ✅ | ✅ | `collectWarnings` checks group policy config |
| `messaging.targetResolver` | ✅ | ✅ | `looksLikeId` + `hint` |
| `messaging.normalizeTarget` | ✅ | ✅ | Strips `telegramuser:`/`tgu:`/`tguser:` prefix |
| `outbound.chunker`/`chunkerMode` | ✅ (`markdown`) | ✅ (`text`) | Exposes `chunkTelegramText` as chunker; text mode (no markdown parsing) |
| `status.probeAccount` | Real probe | ✅ | Uses `adapter.self()` for real MTProto liveness check |
| `directory.self` | ✅ | ✅ | Returns `{id, name}` via `adapter.self()` |
| `meta.docsLabel` | ✅ | ✅ | Added for SDK metadata parity |
| `sendMedia` (photos, documents, etc.) | ✅ | ✅ | `media.ts` — type inference from URL extension; wraps `adapter.sendFile()` |
| `onboarding` flow | ✅ | N/A | Bot-specific; user accounts don't onboard |
| `actions` (bot message actions/buttons) | ✅ | N/A | Bot-specific UI; not applicable to user mode |
| `status.auditAccount` (group audit) | ✅ | ✅ | Iterates configured groups, checks membership via `adapter.isParticipant()` |
| `/tgu_*` commands | ✅ | ✅ | Approval queue commands: list, approve, edit, reject, view, clear |
| Group message handling | ✅ | ✅ | Full `groupPolicy` enforcement (disabled/allowlist/open), per-group config, mention gating |
| Auth CLI | N/A | Out of scope | `stringSession` obtained externally |
| `directory.listPeers`/`listGroups` | ✅ | ✅ | `listPeers` from `allowFrom` config; `listGroups` from `groups` config (filtered) |

## Approval commands

| Command | Description |
|---------|-------------|
| `/tgu_list` | List pending drafts (up to 20) |
| `/tgu_view <id>` | View draft details |
| `/tgu_approve <id>` | Send draft as-is |
| `/tgu_edit <id> <text>` | Replace draft text and send |
| `/tgu_reject <id>` | Discard draft |
| `/tgu_clear [accountId\|all]` | Bulk clear drafts |

When `approval.mode` is `"manual"`, inbound messages generate drafts sent to Saved Messages for review. Use these commands to approve or reject.

## Known limitations

1. **No auth CLI** — `stringSession` obtained externally
2. **Single instance** — one gateway per Telegram account (process-local state)
3. **No webhook** — MTProto long-poll only (MTProto is inherently long-poll)
4. **Text-only chunker** — `chunkerMode: "text"` (no markdown-aware splitting)
5. **No threading** — `threading.resolveReplyToMode` hardcoded `"off"` (MTProto user mode has no bot-style threading)
6. **Connection timeout** — 30s timeout on MTProto connect; retries are handled by GramJS (`connectionRetries: 5`)
7. **Zod version** — Pins `zod@3.24.2`; must match the host runtime version to avoid `schema.toJSONSchema is not a function` errors. Verify compatibility before deploy.

## Draft persistence

Drafts persist at:

- default: `~/.openclaw/state/telegramuser-drafts.json`
- override: `OPENCLAW_TELEGRAMUSER_DRAFTS`

Atomic writes via temp file + rename. Auto-prunes expired drafts on list operations. Queue capped by `rateLimit.maxPendingDrafts` (default 20).

## Group config

Groups are configured per-account under the `groups` key. The `*` key acts as a wildcard default.

```json
{
  "groupPolicy": "allowlist",
  "groups": {
    "*": { "requireMention": true },
    "-1001234567890": { "allow": true, "enabled": true, "requireMention": false }
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `groupPolicy` | `"disabled"` \| `"allowlist"` \| `"open"` | `"disabled"` | Gate for all group messages |
| `groups[id].allow` | `boolean` | `false` | Allow this group (allowlist mode) |
| `groups[id].enabled` | `boolean` | `true` | Enable/disable processing for this group |
| `groups[id].requireMention` | `boolean` | `true` | Only process messages that @mention the account |
| `groups[id].tools` | tool policy | — | Per-group tool policy override |

## Future improvements

1. Markdown-aware chunker mode (`chunkerMode: "markdown"`)
2. Discord escalation for manual approval queue
