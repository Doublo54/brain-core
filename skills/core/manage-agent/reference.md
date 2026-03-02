# Manage Agent — Reference

Detailed health check procedures and archive process.

---

## Health Check Matrix

| Check | How | Pass | Fail |
|-------|-----|------|------|
| Workspace exists | Check directory at registered path | Dir exists with AGENTS.md | Missing or empty |
| Memory files | Check `memory/` for recent `.md` files | Files from last 7 days | No recent files (may be normal for new agents) |
| Hindsight bank | `GET /v1/default/banks/{id}/stats` | 200 + node_count > 0 | 404 or node_count = 0 |
| LanceDB | Check `OPENAI_API_KEY` env + `~/.openclaw/memory/lancedb/` dir | Both present | Missing key or dir |
| QMD binary | `which qmd` | Found on PATH | Not found |
| OpenClaw entry | Read config, find agent in `agents.list` | Entry found with correct workspace | Missing or workspace mismatch |
| Session discovery | `sessions_list` filtered by agent id | Target session identified | No matching session |
| Agent responds (preferred) | `sessions_send` to discovered session with `"health check"` | Gets response | No response/error |
| Agent responds (fallback) | `openclaw agent --agent {id} --message "health check"` (if no session exists) | Gets response | Timeout or error |

## Health Report Format

```markdown
## Agent Health: {name} ({id})

| Check | Status | Details |
|-------|--------|---------|
| Workspace | PASS/FAIL | {path} |
| Memory | PASS/FAIL | {details} |
| Config | PASS/FAIL | {details} |
| Responds | PASS/FAIL | {details} |

**Overall:** HEALTHY / DEGRADED / UNHEALTHY
**Checked:** {timestamp}
```

---

## Archive Process

### Before archive

1. Ensure no active sessions (check `openclaw sessions list --agent {id}`)
2. Commit any pending brain repo changes
3. Push working branch

### Archive steps

1. Remove bindings: delete entries where `agentId = {id}` from `bindings[]`
2. Remove agent: delete entry from `agents.list[]`
3. If agent had a dedicated Discord account: disable it in `channels.discord.accounts.{accountId}.enabled = false`
4. Apply config changes (with approval)
5. Update registry: set status to `archived`, add archive date

### After archive

- Workspace and repo are preserved (can be re-activated later)
- To reactivate: re-add agent entry + bindings, set registry status back to `active`
- Memory/Hindsight data is preserved (banks are not deleted)

---

## Registry Discrepancy Patterns

| Pattern | Meaning | Action |
|---------|---------|--------|
| In registry, not in config | Agent was archived or config was reset | Verify intent, update registry if needed |
| In config, not in registry | Agent was added manually outside create-agent | Add to registry retroactively |
| Workspace path mismatch | Config was updated without updating registry | Update registry to match config |
| Status says active but health fails | Agent is broken | Report to human, suggest troubleshooting |
