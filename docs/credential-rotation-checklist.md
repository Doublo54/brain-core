# Credential Rotation Checklist

This document provides a comprehensive reference for rotating all credentials used by the OpenClaw gateway and agent infrastructure. Each credential is listed with its dashboard URL, environment variable name, which agents use it, the restart procedure, and post-rotation verification commands.

**IMPORTANT**: Credential rotation should be performed during a maintenance window. Always test in a staging environment first.

---

## 1. Anthropic (Claude) API Key

**Service**: Anthropic Claude API  
**Dashboard URL**: https://console.anthropic.com/  
**Environment Variable**: `ANTHROPIC_API_KEY`  
**Used By**: All agents using Claude models (primary LLM provider)  
**Rotation Steps**:
1. Log in to https://console.anthropic.com/
2. Navigate to API Keys section
3. Create a new API key
4. Copy the new key
5. Update `ANTHROPIC_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: `curl -H "Authorization: Bearer $ANTHROPIC_API_KEY" https://api.anthropic.com/v1/models`

**Post-Rotation Verification**:
```bash
# Test Claude API connectivity
curl -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"test"}]}'
```

---

## 2. Anthropic OAuth Token (Claude Code CLI)

**Service**: Anthropic Claude Code CLI  
**Dashboard URL**: https://console.anthropic.com/ (via `claude setup-token`)  
**Environment Variable**: `ANTHROPIC_OAUTH_TOKEN`  
**Used By**: OpenCode server, Claude Code CLI integration  
**Rotation Steps**:
1. Run `claude setup-token` on your local machine
2. Follow the authentication flow
3. Copy the generated `sk-ant-oat01-...` token
4. Update `ANTHROPIC_OAUTH_TOKEN` in `.env` or Coolify dashboard
5. Restart gateway: `docker compose restart openclaw-gateway`
6. Verify: `opencode session list` (should show active sessions)

**Post-Rotation Verification**:
```bash
# Check OpenCode server connectivity
curl http://127.0.0.1:4096/session
```

---

## 3. OpenAI API Key

**Service**: OpenAI GPT API  
**Dashboard URL**: https://platform.openai.com/api-keys  
**Environment Variable**: `OPENAI_API_KEY`  
**Used By**: Agents configured to use GPT models (via OpenRouter or direct)  
**Rotation Steps**:
1. Log in to https://platform.openai.com/
2. Navigate to API Keys
3. Create a new API key
4. Copy the new key
5. Update `OPENAI_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: `curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"`

**Post-Rotation Verification**:
```bash
# Test OpenAI API connectivity
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}]}'
```

---

## 4. OpenRouter API Key

**Service**: OpenRouter (multi-model routing)  
**Dashboard URL**: https://openrouter.ai/  
**Environment Variable**: `OPENROUTER_API_KEY`  
**Used By**: Agents using OpenRouter for model selection and fallback routing  
**Rotation Steps**:
1. Log in to https://openrouter.ai/
2. Navigate to Keys section
3. Create a new API key
4. Copy the new key
5. Update `OPENROUTER_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: `curl https://openrouter.ai/api/v1/models -H "Authorization: Bearer $OPENROUTER_API_KEY"`

**Post-Rotation Verification**:
```bash
# Test OpenRouter API connectivity
curl https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"test"}]}'
```

---

## 5. ZAI API Key

**Service**: ZAI (vision, web-reader, zread MCP servers)  
**Dashboard URL**: https://zai.ai/  
**Environment Variable**: `ZAI_API_KEY`  
**Used By**: zai-vision, web-reader, zread MCP servers  
**Rotation Steps**:
1. Log in to https://zai.ai/
2. Navigate to API Keys or Settings
3. Create a new API key
4. Copy the new key
5. Update `ZAI_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: Check MCP server logs for successful authentication

**Post-Rotation Verification**:
```bash
# Test ZAI API connectivity (if endpoint available)
# Check gateway logs for MCP server initialization
docker compose logs openclaw-gateway | grep -i "zai\|mcp"
```

---

## 6. Kimi Coding API Key

**Service**: Kimi Coding (Chinese LLM provider)  
**Dashboard URL**: https://kimi.moonshot.cn/  
**Environment Variable**: `KIMI_API_KEY`  
**Used By**: Agents configured to use Kimi models  
**Rotation Steps**:
1. Log in to https://kimi.moonshot.cn/
2. Navigate to API Keys or Developer Settings
3. Create a new API key
4. Copy the new key
5. Update `KIMI_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: Test agent with Kimi model selection

**Post-Rotation Verification**:
```bash
# Test Kimi API connectivity (if endpoint available)
# Check agent logs for successful model invocation
docker compose logs openclaw-gateway | grep -i "kimi"
```

---

## 7. OpenCode API Key (ZEN)

**Service**: OpenCode ZEN (model routing and OpenCode server)  
**Dashboard URL**: https://opencode.ai/  
**Environment Variable**: `OPENCODE_API_KEY`  
**Used By**: OpenCode server, model routing via ZEN  
**Rotation Steps**:
1. Log in to https://opencode.ai/
2. Navigate to API Keys or Subscription Settings
3. Create a new API key
4. Copy the new key
5. Update `OPENCODE_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: `curl http://127.0.0.1:4096/session`

**Post-Rotation Verification**:
```bash
# Test OpenCode server connectivity
curl http://127.0.0.1:4096/session
# Check for active sessions
```

---

## 8. Discord Bot Token (Primary)

**Service**: Discord Bot (single-bot mode)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN`  
**Used By**: discord-pipe daemon, primary Discord integration  
**Rotation Steps**:
1. Log in to https://discord.com/developers/applications
2. Select your bot application
3. Navigate to TOKEN section
4. Click "Regenerate" (old token becomes invalid immediately)
5. Copy the new token
6. Update `DISCORD_BOT_TOKEN` in `.env` or Coolify dashboard
7. Restart gateway: `docker compose restart openclaw-gateway`
8. Verify: Bot should reconnect to Discord

**Post-Rotation Verification**:
```bash
# Check bot is online in Discord
# Send a test message to a channel where the bot has permissions
# Verify bot responds or logs show successful connection
docker compose logs discord-pipe | grep -i "connected\|ready"
```

---

## 9. Discord Bot Token 1

**Service**: Discord Bot (multi-bot mode, account 1)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_1`  
**Used By**: Agent 1 Discord integration (multi-bot mode)  
**Rotation Steps**:
1. Log in to https://discord.com/developers/applications
2. Select bot application 1
3. Navigate to TOKEN section
4. Click "Regenerate"
5. Copy the new token
6. Update `DISCORD_BOT_TOKEN_1` in `.env` or Coolify dashboard
7. Restart gateway: `docker compose restart openclaw-gateway`
8. Verify: Bot 1 should reconnect to Discord

**Post-Rotation Verification**:
```bash
# Verify bot 1 is online and responsive
docker compose logs openclaw-gateway | grep -i "discord.*token.*1"
```

---

## 10. Discord Bot Token 2

**Service**: Discord Bot (multi-bot mode, account 2)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_2`  
**Used By**: Agent 2 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 2

**Post-Rotation Verification**:
```bash
# Verify bot 2 is online and responsive
docker compose logs openclaw-gateway | grep -i "discord.*token.*2"
```

---

## 11. Discord Bot Token 3

**Service**: Discord Bot (multi-bot mode, account 3)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_3`  
**Used By**: Agent 3 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 3

---

## 12. Discord Bot Token 4

**Service**: Discord Bot (multi-bot mode, account 4)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_4`  
**Used By**: Agent 4 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 4

---

## 13. Discord Bot Token 5

**Service**: Discord Bot (multi-bot mode, account 5)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_5`  
**Used By**: Agent 5 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 5

---

## 14. Discord Bot Token 6

**Service**: Discord Bot (multi-bot mode, account 6)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_6`  
**Used By**: Agent 6 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 6

---

## 15. Discord Bot Token 7

**Service**: Discord Bot (multi-bot mode, account 7)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_7`  
**Used By**: Agent 7 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 7

---

## 16. Discord Bot Token 8

**Service**: Discord Bot (multi-bot mode, account 8)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_8`  
**Used By**: Agent 8 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 8

---

## 17. Discord Bot Token 9

**Service**: Discord Bot (multi-bot mode, account 9)  
**Dashboard URL**: https://discord.com/developers/applications  
**Environment Variable**: `DISCORD_BOT_TOKEN_9`  
**Used By**: Agent 9 Discord integration (multi-bot mode)  
**Rotation Steps**: Same as Token 1, but for bot application 9

---

## 18. Discord User Token (Selfbot)

**Service**: Discord User Plugin (personal account via discord-user-bots)  
**Dashboard URL**: Discord Developer Tools (Application tab > Local Storage > token)  
**Environment Variable**: `DISCORD_USER_TOKEN`  
**Used By**: discorduser plugin (agent responds as personal Discord account)  
**Rotation Steps**:
1. Open Discord in browser
2. Press F12 to open Developer Tools
3. Go to Application tab > Local Storage > https://discord.com
4. Find the `token` key
5. Copy the new token value
6. Update `DISCORD_USER_TOKEN` in `.env` or Coolify dashboard
7. Restart gateway: `docker compose restart openclaw-gateway`
8. Verify: Agent can send messages as your personal account

**Post-Rotation Verification**:
```bash
# Check discorduser plugin logs
docker compose logs openclaw-gateway | grep -i "discorduser\|selfbot"
```

**WARNING**: Using selfbots violates Discord ToS. Use at your own risk.

---

## 19. Telegram Bot Token

**Service**: Telegram Bot API  
**Dashboard URL**: https://t.me/BotFather  
**Environment Variable**: `TELEGRAM_BOT_TOKEN`  
**Used By**: Telegram bot integration (agent responds to Telegram messages)  
**Rotation Steps**:
1. Open Telegram and message @BotFather
2. Send `/mybots` to list your bots
3. Select the bot to rotate
4. Select "API Token"
5. Confirm token regeneration
6. Copy the new token
7. Update `TELEGRAM_BOT_TOKEN` in `.env` or Coolify dashboard
8. Restart gateway: `docker compose restart openclaw-gateway`
9. Verify: Bot should reconnect to Telegram

**Post-Rotation Verification**:
```bash
# Send a test message to the bot
# Verify bot responds
docker compose logs openclaw-gateway | grep -i "telegram.*connected"
```

---

## 20. Telegram API ID

**Service**: Telegram MTProto (personal account)  
**Dashboard URL**: https://my.telegram.org/apps  
**Environment Variable**: `TELEGRAM_API_ID`  
**Used By**: telegramuser plugin (agent responds as personal Telegram account)  
**Rotation Steps**:
1. Log in to https://my.telegram.org/
2. Navigate to API Development Tools
3. Create a new application or edit existing
4. Copy the API ID
5. Update `TELEGRAM_API_ID` in `.env` or Coolify dashboard
6. Regenerate `TELEGRAM_STRING_SESSION` (see below)
7. Restart gateway: `docker compose restart openclaw-gateway`

**Post-Rotation Verification**:
```bash
# Verify telegramuser plugin can authenticate
docker compose logs openclaw-gateway | grep -i "telegramuser\|mtproto"
```

---

## 21. Telegram API Hash

**Service**: Telegram MTProto (personal account)  
**Dashboard URL**: https://my.telegram.org/apps  
**Environment Variable**: `TELEGRAM_API_HASH`  
**Used By**: telegramuser plugin (agent responds as personal Telegram account)  
**Rotation Steps**:
1. Log in to https://my.telegram.org/
2. Navigate to API Development Tools
3. Create a new application or edit existing
4. Copy the API Hash
5. Update `TELEGRAM_API_HASH` in `.env` or Coolify dashboard
6. Regenerate `TELEGRAM_STRING_SESSION` (see below)
7. Restart gateway: `docker compose restart openclaw-gateway`

**Post-Rotation Verification**:
```bash
# Verify telegramuser plugin can authenticate
docker compose logs openclaw-gateway | grep -i "telegramuser\|mtproto"
```

---

## 22. Telegram String Session

**Service**: Telegram MTProto (personal account session)  
**Dashboard URL**: Generated via `make telegram-session`  
**Environment Variable**: `TELEGRAM_STRING_SESSION`  
**Used By**: telegramuser plugin (persistent session for personal account)  
**Rotation Steps**:
1. Stop the gateway: `docker compose down`
2. Run: `make telegram-session`
3. Follow the authentication flow (scan QR code or enter phone + code)
4. Copy the generated stringSession
5. Update `TELEGRAM_STRING_SESSION` in `.env` or Coolify dashboard
6. Start gateway: `docker compose up -d`
7. Verify: Agent can send messages as your personal account

**Post-Rotation Verification**:
```bash
# Verify telegramuser plugin is authenticated
docker compose logs openclaw-gateway | grep -i "telegramuser.*authenticated"
```

**IMPORTANT**: Each stringSession can only be used by ONE process at a time. Stop the gateway before regenerating.

---

## 23. GitHub Personal Access Token (PAT)

**Service**: GitHub API & Git Operations  
**Dashboard URL**: https://github.com/settings/tokens  
**Environment Variable**: `GITHUB_TOKEN`  
**Used By**: Brain repo sync (entrypoint.sh), git operations in orchestration scripts  
**Rotation Steps**:
1. Log in to https://github.com/
2. Navigate to Settings > Developer settings > Personal access tokens > Tokens (classic)
3. Create a new token with `repo` and `read:org` scopes
4. Copy the new token
5. Update `GITHUB_TOKEN` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: Brain repo sync should work on next restart

**Post-Rotation Verification**:
```bash
# Test GitHub API connectivity
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user

# Verify brain repo sync works
docker compose logs openclaw-gateway | grep -i "brain.*cloned\|brain.*updated"
```

---

## 24. ClickUp API Key

**Service**: ClickUp Task Management  
**Dashboard URL**: https://app.clickup.com/settings/integrations  
**Environment Variable**: `CLICKUP_API_KEY`  
**Used By**: ClickUp MCP server, task management integration  
**Rotation Steps**:
1. Log in to https://app.clickup.com/
2. Navigate to Settings > Integrations > API
3. Create a new API token
4. Copy the new token
5. Update `CLICKUP_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: ClickUp MCP server should initialize successfully

**Post-Rotation Verification**:
```bash
# Check ClickUp MCP server logs
docker compose logs openclaw-gateway | grep -i "clickup\|mcp"
```

---

## 25. Brave Search API Key

**Service**: Brave Search API  
**Dashboard URL**: https://api.search.brave.com/  
**Environment Variable**: `BRAVE_API_KEY`  
**Used By**: Brave Search integration for web search queries  
**Rotation Steps**:
1. Log in to https://api.search.brave.com/
2. Navigate to API Keys or Dashboard
3. Create a new API key
4. Copy the new key
5. Update `BRAVE_API_KEY` in `.env` or Coolify dashboard
6. Restart gateway: `docker compose restart openclaw-gateway`
7. Verify: Web search queries should work

**Post-Rotation Verification**:
```bash
# Test Brave Search API connectivity
curl -H "Accept: application/json" \
  "https://api.search.brave.com/res/v1/web/search?q=test&count=1&api_key=$BRAVE_API_KEY"
```

---

## 26. Google Workspace Client ID

**Service**: Google Cloud OAuth 2.0  
**Dashboard URL**: https://console.cloud.google.com/apis/credentials  
**Environment Variable**: `GOOGLE_WORKSPACE_CLIENT_ID`  
**Used By**: workspace-mcp (Google Workspace integration)  
**Rotation Steps**:
1. Log in to https://console.cloud.google.com/
2. Navigate to APIs & Services > Credentials
3. Select your OAuth 2.0 Desktop Application
4. Create a new OAuth 2.0 Client ID (or regenerate)
5. Copy the new Client ID
6. Update `GOOGLE_WORKSPACE_CLIENT_ID` in `.env` or Coolify dashboard
7. Regenerate `GOOGLE_WORKSPACE_CLIENT_SECRET` (see below)
8. Restart gateway: `docker compose restart openclaw-gateway`

**Post-Rotation Verification**:
```bash
# Verify workspace-mcp can authenticate
docker compose logs openclaw-gateway | grep -i "workspace.*oauth\|google.*authenticated"
```

---

## 27. Google Workspace Client Secret

**Service**: Google Cloud OAuth 2.0  
**Dashboard URL**: https://console.cloud.google.com/apis/credentials  
**Environment Variable**: `GOOGLE_WORKSPACE_CLIENT_SECRET`  
**Used By**: workspace-mcp (Google Workspace integration)  
**Rotation Steps**:
1. Log in to https://console.cloud.google.com/
2. Navigate to APIs & Services > Credentials
3. Select your OAuth 2.0 Desktop Application
4. Create a new OAuth 2.0 Client ID (or regenerate)
5. Copy the new Client Secret
6. Update `GOOGLE_WORKSPACE_CLIENT_SECRET` in `.env` or Coolify dashboard
7. Restart gateway: `docker compose restart openclaw-gateway`

**Post-Rotation Verification**:
```bash
# Verify workspace-mcp can authenticate
docker compose logs openclaw-gateway | grep -i "workspace.*oauth\|google.*authenticated"
```

**IMPORTANT**: Set publishing status to "In production" — Testing mode tokens expire after 7 days.

---

## 28. OpenClaw Gateway Token

**Service**: OpenClaw Gateway Authentication  
**Dashboard URL**: Local configuration (generated via `openssl rand -hex 32`)  
**Environment Variable**: `OPENCLAW_GATEWAY_TOKEN`  
**Used By**: Gateway authentication, device pairing, browser tool access  
**Rotation Steps**:
1. Generate a new token: `openssl rand -hex 32`
2. Update `OPENCLAW_GATEWAY_TOKEN` in `.env` or Coolify dashboard
3. Restart gateway: `docker compose restart openclaw-gateway`
4. Verify: Device pairing should work with new token

**Post-Rotation Verification**:
```bash
# Test gateway connectivity with new token using a WebSocket client
wscat -c ws://127.0.0.1:18789/ \
  -H "Authorization: Bearer $OPENCLAW_GATEWAY_TOKEN"
```

---

## General Rotation Best Practices

1. **Staging First**: Always test credential rotation in a staging environment before production
2. **Maintenance Window**: Perform rotations during low-traffic periods
3. **Backup Old Credentials**: Keep old credentials for 24-48 hours in case rollback is needed
4. **Monitor Logs**: Check gateway and agent logs after rotation for authentication errors
5. **Verify Functionality**: Test each service after rotation to ensure it's working
6. **Document Changes**: Record when credentials were rotated and by whom
7. **Automate Where Possible**: Use CI/CD pipelines to automate credential updates
8. **Audit Trail**: Enable audit logging for credential access and rotation events

---

## Credential Expiration Schedule

| Credential | Recommended Rotation | Notes |
|-----------|---------------------|-------|
| API Keys (Anthropic, OpenAI, etc.) | Every 90 days | Rotate sooner if compromised |
| GitHub PAT | Every 90 days | Use fine-grained tokens when possible |
| Discord Bot Tokens | Every 180 days | Regenerate immediately if leaked |
| Telegram Tokens | Every 180 days | Session tokens may expire naturally |
| Google OAuth | Every 90 days | Testing mode tokens expire after 7 days |
| Gateway Token | Every 180 days | Rotate during maintenance window |

---

## Emergency Credential Revocation

If a credential is compromised:

1. **Immediately revoke** the credential in its dashboard
2. **Generate a new credential** with the same or higher permissions
3. **Update** the environment variable in `.env` or Coolify dashboard
4. **Restart** the affected service
5. **Monitor** logs for any unauthorized access attempts
6. **Audit** recent activity logs for the compromised credential
7. **Document** the incident and remediation steps

---

## Credential Storage Best Practices

- **Never commit credentials** to version control (use `.env.example` instead)
- **Use `.env.example`** to document required variables without secrets
- **Restrict file permissions** on `.env` files (chmod 600)
- **Use secrets management** systems (Coolify, Vault, etc.) in production
- **Rotate credentials regularly** even if not compromised
- **Audit credential access** and usage patterns
- **Use service accounts** instead of personal credentials when possible
- **Enable MFA** on all credential dashboards
