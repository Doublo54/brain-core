# Google Workspace MCP Integration

Uses [`workspace-mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) (PyPI: `workspace-mcp`) — the most feature-complete Google Workspace MCP server available. Covers Gmail, Drive, Calendar, Docs, Sheets, Slides, Forms, Tasks, Contacts, Chat, and Search.

## Why this package

- 1.4k+ stars, actively maintained, MIT licensed
- Covers entire Google Workspace suite (not just Drive)
- OAuth 2.0 + 2.1 support with automatic token refresh
- Tool tiers (`core`, `extended`, `complete`) to limit exposed capabilities
- Read-only mode available for restricted agents
- CLI mode for scripting and automation

Replaces the previous `@chinchillaenterprises/mcp-google-drive` which only supported Drive reads.

## MCP config entry

Configured in `brain-core/config/mcporter.json` as:

```json
{
  "google-workspace": {
    "command": "uvx",
    "args": ["workspace-mcp", "--single-user", "--tool-tier", "core"],
    "env": {
      "GOOGLE_OAUTH_CLIENT_ID": "${GOOGLE_WORKSPACE_CLIENT_ID}",
      "GOOGLE_OAUTH_CLIENT_SECRET": "${GOOGLE_WORKSPACE_CLIENT_SECRET}",
      "USER_GOOGLE_EMAIL": "${GOOGLE_WORKSPACE_EMAIL}"
    }
  }
}
```

### Tool tiers

| Tier | Scope | Use case |
|------|-------|----------|
| `core` | Essential read/write per service | Default for Standard-tier agents |
| `extended` | Core + additional operations | Trusted-tier agents |
| `complete` | All tools exposed | Admin-tier only |

### Runtime flags

- `--single-user` — Uses cached OAuth tokens (no interactive flow per request)
- `--read-only` — Restricts to read-only scopes (good for restricted agents)
- `--tools gmail drive` — Load only specific services

## Google Cloud OAuth setup

1. Create a Google Cloud project at https://console.cloud.google.com
2. Enable required APIs (Drive, Docs, Sheets, Gmail, Calendar, etc.)
3. Configure OAuth consent screen:
   - User type: External (or Internal for Workspace orgs)
   - Add test users during development
4. Create OAuth credentials:
   - Type: OAuth Client ID
   - App type: **Desktop Application** (no redirect URIs needed)
5. Generate a refresh token via OAuth Playground or the workspace-mcp built-in auth flow

## Required environment variables

Set in the runtime environment (e.g., `.env` consumed by your stack):

- `GOOGLE_WORKSPACE_CLIENT_ID` — OAuth client ID
- `GOOGLE_WORKSPACE_CLIENT_SECRET` — OAuth client secret
- `GOOGLE_WORKSPACE_EMAIL` — Default user email for single-user auth

No credentials are stored in repo config; `mcporter.json` only uses `${...}` placeholders.

## Container requirements

The Docker image needs `uv`/`uvx` installed (Python package manager). This is added to the Dockerfile's `base-common` stage.

## Container deployment

- **The problem**: `workspace-mcp` runs an OAuth callback server on `localhost:8000` inside the container. The user's browser cannot reach it. Credentials are ephemeral without a volume.
- **The solution**: Pre-authenticate locally, mount credentials into the container.
  - **Step 1**: Run `uvx workspace-mcp --single-user --tool-tier core` locally with env vars set. Complete OAuth in browser. Token saved to `~/.google_workspace_mcp/credentials/{email}.json`.
  - **Step 2**: The Docker stack mounts a `google_workspace_creds` volume at `/home/node/.google_workspace_mcp/credentials/`. Copy the local credential file into this volume (for Coolify: via SSH to the host, `docker cp`, or Coolify terminal).
  - **Step 3**: Set `WORKSPACE_MCP_CREDENTIALS_DIR=/home/node/.google_workspace_mcp/credentials` (already configured in docker-compose). Token refresh is automatic — `workspace-mcp` uses the `refresh_token` and saves updated credentials back.

### Environment variables required in docker-compose

- `GOOGLE_WORKSPACE_CLIENT_ID`
- `GOOGLE_WORKSPACE_CLIENT_SECRET`
- `GOOGLE_WORKSPACE_EMAIL`
- `WORKSPACE_MCP_CREDENTIALS_DIR` (set automatically by docker-compose)

### Token lifecycle warning

Google OAuth apps in "Testing" publishing status have refresh tokens that **expire after 7 days**. For unattended agent operation, the OAuth app MUST be published to "In production" status. This requires a privacy policy URL and Google verification for sensitive scopes (Gmail, etc.). Non-sensitive scopes (Drive, Calendar, Sheets) have a faster verification path.

### Credential file format

```json
{
  "token": "ya29.a0...",
  "refresh_token": "1//...",
  "token_uri": "https://oauth2.googleapis.com/token",
  "client_id": "...",
  "client_secret": "...",
  "scopes": ["..."],
  "expiry": "2026-02-15T00:00:00"
}
```

## Known limitations

- OAuth only (no service account support) — same as all Google MCP packages evaluated
- First-time auth requires a local browser flow; see Container deployment above for remote/Docker setup
- OAuth apps in Testing status have 7-day token expiry — publish to Production for permanent refresh tokens
- Token lifecycle management (rotation/revocation) is an operational concern

## Future improvements

- Service account support when upstream adds it or via custom fork
- Per-tier tool restriction (Standard gets `core`, Trusted gets `extended`)
- Automated token refresh/rotation in unattended agent operation
