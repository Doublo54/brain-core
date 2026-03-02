# opencode-discord-pipe

Real-time pipe from OpenCode's SSE event stream to Discord channels.

## Architecture

```
OpenCode Server (:4096)
    │
    ├─ GET /event (SSE stream)
    │
    ▼
opencode-discord-pipe (Node.js daemon)
    │
    ├─► #opencode-status    — session lifecycle (create/idle/step-finish)
    ├─► #opencode-agent     — agent text responses
    ├─► #opencode-tools     — tool calls & results
    ├─► #opencode-diffs     — code changes (unified diffs)
    └─► #opencode-thinking  — reasoning / chain-of-thought
```

## SSE Event Types → Channel Routing

| SSE Event | Channel | Description |
|-----------|---------|-------------|
| `session.created` | status | New session started |
| `session.idle` | status | Session completed |
| `message.part.updated` (type=step-finish) | status | Step done with token/cost info |
| `message.part.updated` (type=text, assistant) | agent | Agent's text response |
| `message.part.updated` (type=tool) | tools | Tool call input/output |
| `session.diff` | diffs | File changes |
| `message.part.updated` (type=reasoning) | thinking | Chain-of-thought |

Filtered out: `tui.toast.show` (OHO animation noise)

## Discord Channels

Guild: `YOUR_GUILD_ID` / Category: `opencode` (`YOUR_CATEGORY_ID`)

| Channel | ID |
|---------|-----|
| opencode-status | `YOUR_CHANNEL_STATUS` |
| opencode-agent | `YOUR_CHANNEL_AGENT` |
| opencode-tools | `YOUR_CHANNEL_TOOLS` |
| opencode-diffs | `YOUR_CHANNEL_DIFFS` |
| opencode-thinking | `YOUR_CHANNEL_THINKING` |

## Running

```bash
# With bot token (live mode)
DISCORD_BOT_TOKEN=xxx npx tsx pipe.ts

# Dry-run (stdout only)
npx tsx pipe.ts

# Via startup script
./start.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DISCORD_BOT_TOKEN` | *(required)* | Discord bot token |
| `OPENCODE_URL` | `http://localhost:4096` | OpenCode server URL |
| `CHANNEL_AGENT` | `YOUR_CHANNEL_AGENT` | Agent responses channel |
| `CHANNEL_TOOLS` | `YOUR_CHANNEL_TOOLS` | Tool calls channel |
| `CHANNEL_DIFFS` | `YOUR_CHANNEL_DIFFS` | Code diffs channel |
| `CHANNEL_THINKING` | `YOUR_CHANNEL_THINKING` | Thinking/reasoning channel |
| `CHANNEL_STATUS` | `YOUR_CHANNEL_STATUS` | Session lifecycle channel |

## Features

- **Real-time SSE**: Subscribes to OpenCode's event stream — no polling
- **Debounced text**: Waits for streaming text to finish before posting
- **Tool dedup**: Only posts tool results on completion (not intermediate states)
- **Per-channel serialization**: Rate-limit safe with per-channel send queues
- **Auto-reconnect**: Exponential backoff on SSE disconnect
- **Session tracking**: Pre-loads existing sessions on startup
- **Per-session threads**: Groups all messages for a session into Discord threads per channel
- **Daemon mode**: Auto-restart on crash, PID management, log rotation
- **Auto-start**: Starts automatically on container boot via docker-compose
- **Graceful shutdown**: Signal handlers for clean SIGTERM/SIGINT exit
- **Output sanitization**: Redacts secrets/tokens from tool output before posting
- **Bounded retries**: Rate limit retries capped at 5 attempts

## Future

- [ ] Message summary diffs (for the diffs channel — needs git integration)
- [ ] Configurable verbosity levels
- [ ] Per-agent channel routing
- [ ] Metrics / token usage aggregation
