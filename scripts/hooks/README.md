# Entrypoint Hooks

Hook scripts are executed by the gateway entrypoint **before** the gateway starts.

## Contract

- **Location:** `$OPENCLAW_HOOKS_DIR` (default: `/home/node/.openclaw/hooks/`)
- **Execution order:** Lexicographic (use numeric prefixes: `00-`, `10-`, `20-`)
- **Interpreter:** Each script is run via `sh <script>`
- **Failure handling:** Non-fatal. A failing hook logs an error and execution continues.
- **Timing:** Hooks run after config generation (step 1), mcporter provisioning (step 2), and OpenCode server startup (step 3), but before the gateway process starts (step 5). OpenCode is guaranteed to be ready when hooks execute.

## Usage

Place `.sh` files on the persistent volume at `~/.openclaw/hooks/`. They will be picked up on every container boot.

For first-deploy convenience, example hooks are baked into the image at `/opt/hooks/`. To activate one:

```bash
# From Coolify Terminal on the openclaw container:
mkdir -p /home/node/.openclaw/hooks
cp /opt/hooks/00-example.sh /home/node/.openclaw/hooks/00-discord.sh
```

## Built-in (handled by entrypoint)

OpenCode bootstrap and server startup are built into the entrypoint (step 3). You do **not** need a hook for these.

## Typical Hooks

| Hook | Purpose |
|------|---------|
| Discord pipe daemon | Route OpenCode SSE events to Discord channels |
| Custom cron | Register periodic tasks |
| Monitoring setup | Additional health check integrations |

## Writing a Hook

```sh
#!/bin/sh
# 10-my-hook.sh — Description of what this does
set -e

echo "[hook:my-hook] Starting..."
# Your logic here
echo "[hook:my-hook] Done"
```

Hooks have access to all environment variables passed to the gateway container.
