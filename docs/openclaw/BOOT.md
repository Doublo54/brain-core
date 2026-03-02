# BOOT.md — Gateway Restart Checklist

*Executed when the OpenClaw gateway restarts (if internal hooks are enabled).*
*Keep this short to avoid token burn on every restart.*

## On Restart

1. Read `CONTEXT.md` — restore working state
2. Check `memory/` for today's log — any pending work?
3. If channels are configured, verify they're connected

<!-- Add startup tasks here as your agent evolves.
     Examples:
     - Check git status of brain repo
     - Verify MCP servers are reachable
     - Send a "back online" notification
-->
