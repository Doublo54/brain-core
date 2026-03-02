# OpenClaw Configuration Backup Process

> **Platform note:** This file applies only to agents running on the OpenClaw platform. If you're using Cursor or another platform, you can safely delete this file.

## Overview

This repository serves as the **source of truth** for OpenClaw configuration. The main config file (`/home/node/.openclaw/openclaw.json`) defines agent(s) and all system-level settings.

## ⚠️ Config Change Protocol

**ALL configuration changes require explicit approval from the admin before execution.**

When you request a config change, the agent will:
1. **Show you the proposed change** (diff, description, or full patch)
2. **Wait for your explicit approval** before applying it
3. **Never auto-apply** based on implied intent or assumptions

This applies to:
- Channel configurations (adding/removing/modifying)
- Agent settings (models, workspaces, tool policies)
- Tool restrictions (allow/deny lists)
- Gateway settings (auth, ports, bindings)
- Any use of `gateway config.patch` or `gateway config.apply`

**Example flow:**
```
You: "Add me to channel X with no exec access"
Agent: [shows proposed config patch]
           "Should I apply this?"
You: "yes" / "approved" / "go ahead"
Agent: [applies config]
```

## Files

- **`openclaw.json`** - Redacted configuration (safe to commit)
- **`openclaw.json.backup`** - Full backup with secrets (`.gitignore`d, never commit)

## Backup Workflow

### When to Backup

Backup the config file **immediately after** you make changes via:
- `gateway config.patch`
- `gateway config.apply`
- Manual edits to `/home/node/.openclaw/openclaw.json`
- Adding/removing agents
- Changing channel configurations
- Updating tool policies

**Timestamp freshness:** The config's `meta.lastTouchedAt` should match your recent changes. If it's stale (hours or days old), refresh the backup before committing to ensure you're capturing the current state.

### How to Backup

#### Step 1: Copy the Live Config
```bash
cd /home/node/.openclaw/workspace
cp /home/node/.openclaw/openclaw.json openclaw.json.backup
```

#### Step 2: Create Redacted Version
```bash
# Copy backup to working file
cp openclaw.json.backup openclaw.json

# Manually redact sensitive values:
# - env.vars.* (all token/key values)
# - channels.*.accounts.*.token
# - gateway.auth.token
# - gateway.auth.password
# - Any API keys or auth credentials
# Replace with: "REDACTED"

# Verify no tokens remain (exit 0 = clean, exit 1 = found tokens)
if grep -qE 'sk-|ghp_|xoxb-|Bot [A-Za-z0-9_-]{50,}|discord\.com.*token|[MN][A-Za-z0-9]{23,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}' openclaw.json; then
  echo "⚠️  WARNING: Found potential un-redacted token!"
  echo "Review the file before committing."
else
  echo "✓ Redaction verification passed"
fi

# Clean up the backup file (contains secrets)
rm openclaw.json.backup

# Verify against last committed version (catch stale snapshots/accidental secrets)
git diff openclaw.json | head -50
# Review the diff - look for:
# - Unexpected changes beyond your recent config edits
# - Any un-redacted tokens that slipped through
# - Timestamp freshness (lastTouchedAt should be recent)
```

**What to Redact:**
- ✅ Auth tokens (Discord, Telegram, GitHub, etc.)
- ✅ API keys
- ✅ Passwords
- ✅ Gateway auth token
- ❌ Keep: User IDs, Channel IDs, Guild IDs (not sensitive)
- ❌ Keep: Configuration structure, agent definitions, tool policies

#### Step 3: Commit to Branch
```bash
git checkout -b config-update-YYYY-MM-DD
git add openclaw.json CONFIG_BACKUP.md
git commit -m "config: update for [describe change]" \
           -m "[what changed]" \
           -m "[why]"
```

#### Step 4: Push and Create PR
```bash
git push origin config-update-YYYY-MM-DD
# Then create PR on GitHub
```

## Why This Process?

1. **Version Control** - Track configuration history and changes over time
2. **Disaster Recovery** - Restore config if system is rebuilt
3. **Documentation** - Config serves as documentation for the system setup
4. **Collaboration** - Admin can review and approve config changes
5. **Security** - Redacted version is safe to store in git

## Important Notes

- **Never commit `openclaw.json.backup`** (it's in `.gitignore`)
- **Always use PRs** for config changes (no direct commits to main)
- **Keep IDs intact** - User/Channel/Guild IDs are not secrets
- **Test after restore** - Always verify config after manual edits

## Full Restore Process

If you need to restore from backup:

1. Accept/merge the PR with the latest config
2. **Dry-run verification** (recommended):
   ```bash
   # Compare tracked config with current live config
   diff /home/node/.openclaw/workspace/openclaw.json /home/node/.openclaw/openclaw.json | head -20
   ```
3. Copy the redacted config to live location:
   ```bash
   cp /home/node/.openclaw/workspace/openclaw.json /home/node/.openclaw/openclaw.json
   ```
4. Manually replace all `"REDACTED"` values with actual secrets from:
   - Environment variables
   - Password manager
   - Secure notes
5. Restart the gateway:
   ```bash
   openclaw gateway restart
   ```
6. Verify both agents are working correctly

## Config Change Checklist

Before committing config changes:
- [ ] Made a backup copy (`openclaw.json.backup`)
- [ ] Redacted all sensitive tokens/keys
- [ ] Kept all IDs (user/channel/guild) intact
- [ ] Tested the change works on live system
- [ ] Documented what changed in commit message
- [ ] Created PR (not direct commit to main)
- [ ] Noted any manual post-restore steps needed

---

**Last Updated:** 2026-02-03
**Maintained By:** Agent
