# DiscordUser Extension

Discord userbot plugin for OpenClaw using discord-user-bots (DUB) library.

## Files

- `src/userbot-runtime.ts` - Plugin runtime management
- `src/userbot-config-schema.ts` - Zod schema for `channels.discorduser` config
- `src/userbot-accounts.ts` - Multi-account resolution utilities

## Configuration

Config path: `channels.discorduser`

### Token Resolution Priority

1. Environment variable `DISCORD_USER_TOKEN` (for default account only)
2. Config field `token` (for default or named accounts)

**Important**: User tokens do NOT use the `"Bot "` prefix (unlike bot tokens).

### Multi-Account Token Configuration

The `DISCORD_USER_TOKEN` environment variable is only used for the **default** account.
If you configure multiple accounts via `accounts` in `openclaw.json`, each account must
have its token set directly in the config file — environment variables are not resolved
for named accounts.

### Example Config

```json
{
  "channels": {
    "discorduser": {
      "enabled": true,
      "token": "user-token-here",
      "dmPolicy": "pairing",
      "approval": {
        "mode": "manual",
        "timeoutSeconds": 300,
        "notifySavedMessages": true
      },
      "rateLimit": {
        "minIntervalSeconds": 2,
        "maxPendingDrafts": 20
      },
      "guilds": {
        "guild-id": {
          "channels": {
            "channel-id": {
              "allow": true,
              "requireMention": false
            }
          }
        }
      },
      "accounts": {
        "sales": {
          "name": "Sales Account",
          "token": "sales-token-here",
          "enabled": true
        }
      }
    }
  }
}
```

## Testing

Tests require OpenClaw SDK to be installed. To run tests:

```bash
cd plugins/discorduser
bun run test-userbot-config.ts    # Validate config schema
bun run test-userbot-accounts.ts  # Validate account resolution
```

## Account Management

- Default account ID: `DEFAULT_ACCOUNT_ID` (from SDK)
- Named accounts: `channels.discorduser.accounts.{accountId}`
- Functions:
  - `listDiscordUserAccountIds(cfg)` - List all account IDs
  - `resolveDiscordUserAccount({ cfg, accountId })` - Resolve account config
  - `setAccountEnabled({ cfg, accountId, enabled })` - Enable/disable account
  - `deleteAccount({ cfg, accountId })` - Delete named account
  - `describeAccount(account)` - Human-readable description
  - `isConfigured(account)` - Check if token is configured
