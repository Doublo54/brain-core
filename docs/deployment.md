# Deployment Runbook

OpenClaw gateway deployment on Hetzner via Coolify.

Everything in this runbook is done through the **Coolify UI** unless explicitly noted otherwise.

> **Before you start:** Read [dood-path-mapping.md](dood-path-mapping.md) and [security-model.md](security-model.md) for critical background on how sandbox workspaces and security boundaries work.

---

## Architecture

```
Docker Compose Stack (Coolify-managed)
├── openclaw-gateway          ← main process, uses DOCKER_HOST to reach proxy
│     ├── rag-network         ← talks to Hindsight, sandbox containers
│     └── openclaw-internal   ← talks to docker-proxy
├── docker-proxy              ← filtered Docker API (tecnativa/docker-socket-proxy)
│     └── openclaw-internal   ← only reachable by gateway
├── sandbox-builder           ← builds sandbox image, exits (exclude_from_hc)
└── volume-init            ← volume ownership provisioning, exits

Spawned outside compose (DooD siblings on host Docker):
└── openclaw-sbx-*            ← sandbox containers, on rag-network only
```

- Sandbox containers are **DooD siblings** — spawned by the gateway via the Docker API proxy
- The Docker Socket Proxy only allows container/exec/image/network endpoints
- Sandbox containers join `rag-network` (can reach Hindsight), NOT `openclaw-internal` (cannot reach docker-proxy)

---

## Repo Structure

```
brain-core/
├── docker/
│   ├── docker-compose.coolify.yml  ← compose file (set in Coolify)
│   ├── Dockerfile                  ← multi-stage: gateway + sandbox targets
│   └── entrypoint.sh              ← gateway runtime entrypoint (hook-based)
├── config/
│   ├── openclaw.json.template     ← auto-generated on first boot via envsubst
│   └── mcporter.json              ← MCP server config (env var refs, no secrets)
├── scripts/
│   ├── bootstrap-opencode.sh      ← OpenCode/OHO persistent setup
│   └── hooks/                     ← example hook scripts
└── docs/
    ├── deployment.md              ← this file
    ├── dood-path-mapping.md       ← workspace path resolution for DooD
    └── security-model.md          ← trust model and network isolation
```

**Build context:** The compose file uses `context: ..` (repo root) so the Dockerfile can COPY from `config/` and `scripts/`. Coolify Base Directory should be set to `/docker`.

---

## Coolify Project Setup (One-time)

### 1. Create a new resource

1. In Coolify dashboard, open your project and click **Create New Resource**
2. Select your Git source (GitHub App or public repo)
3. Point it to the brain-core repository and select the deployment branch

### 2. Select build pack

1. Change the build pack from Nixpacks to **Docker Compose**
2. Set **Base Directory** to `/docker` (where the compose file lives)
3. Set **Docker Compose Location** to: `docker-compose.coolify.yml`

The compose references the Dockerfile via `context: ..` and `dockerfile: docker/Dockerfile`, so the build context is the repo root. This allows the Dockerfile to COPY config and script files.

### 3. Service configuration

After Coolify loads the compose file, it will show four services:
- **openclaw** — the gateway (main service)
- **docker-proxy** — socket proxy (no domain needed, internal only)
- **sandbox-builder** — init container (auto-excluded from health checks)
- **volume-init** — volume permissions (auto-excluded from health checks)

Only `openclaw` needs a domain (if you want external access) or port mapping. The published port is configurable via `OPENCLAW_GATEWAY_HOST_BIND`, `OPENCLAW_GATEWAY_HOST_PORT`, and `OPENCLAW_GATEWAY_PORT` (defaults: `127.0.0.1:18789:18789`).

---

## Deploy via Coolify UI

### Step 3.5: Preflight (before clicking Deploy)

Run this from your workstation for the exact branch Coolify will deploy:

```bash
# From brains/ workspace root
bash brain-core/scripts/validate-permissions.sh \
  --config defizoo-brain/config/openclaw.json.template \
  --brain-dir defizoo-brain/agents

docker compose -f brain-core/docker/docker-compose.coolify.yml config --quiet
```

Expected result: permission validation passes for all agents and compose validation exits 0.

### Step 4: Environment Variables

In Coolify, go to your OpenClaw service > **Environment Variables**.

Coolify auto-detects variables from the compose file. Set these values:

#### Required

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | (none) | Gateway auth token. **Required.** |
| `BRAIN_GIT_REPO` | (empty) | Brain repository to clone at startup (format: `org/repo`). |
| `GITHUB_TOKEN` | (empty) | GitHub token used to clone/pull `BRAIN_GIT_REPO`. Required when `BRAIN_GIT_REPO` is set. |
| `BRAIN_HOST_PATH` | (empty) | Host-absolute brain path used by sandbox DooD mounts. Set after first deploy once Coolify volume name is known. |
| `OPENCLAW_CONFIG_TEMPLATE` | `/opt/brain/config/openclaw.json.template` | Template path used on first boot. Keep default when brain repo provides its own template. |

#### Brain Git Sync

| Variable | Default | Description |
|----------|---------|-------------|
| `BRAIN_GIT_BRANCH` | `main` | Branch cloned into `/opt/brain`. |
| `BRAIN_LIVE_BRANCH` | `live` | Working branch used by agent commits/heartbeats. |

#### Gateway Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_VERSION` | `v2026.2.15` | OpenClaw version tag to build from source. |
| `OPENCLAW_GATEWAY_HOST_BIND` | `127.0.0.1` | Host interface for published port. |
| `OPENCLAW_GATEWAY_HOST_PORT` | `18789` | Host port mapped to the gateway container. |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway listen port inside container. |
| `OPENCLAW_GATEWAY_BIND` | `lan` | Gateway bind mode. |
| `TZ` | `UTC` | Container timezone. |

#### Agent Configuration (used by config template on first boot)

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_DEFAULT_MODEL` | `anthropic/claude-sonnet-4-5` | Default model for agents. |
| `OPENCLAW_AGENT_NAME` | `Agent` | Main agent display name. |
| `OPENCLAW_USER_TIMEZONE` | `UTC` | Agent timezone (e.g., `America/Sao_Paulo`). |
| `OPENCLAW_ADMIN_DISCORD_ID` | (empty) | Your Discord user ID for DM allowlist + elevated tools. |
| `OPENCLAW_ADMIN_TELEGRAM_ID` | (empty) | Your Telegram user ID. |

#### Provider API Keys

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI |
| `OPENROUTER_API_KEY` | OpenRouter |
| `ZAI_API_KEY` | ZAI (also powers MCP servers: zai-vision, web-reader, zread) |
| `KIMI_API_KEY` | Kimi Coding |

#### Channel & Service Tokens

| Variable | Description |
|----------|-------------|
| `DISCORD_BOT_TOKEN_1` ... `DISCORD_BOT_TOKEN_9` | Discord bot tokens mapped to `channels.discord.accounts` in `openclaw.json.template` |
| `DISCORD_BOT_TOKEN` | Optional single-bot token (non multi-account setups) |
| `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_STRING_SESSION` | Required for `telegramuser` plugin |
| `DISCORD_USER_TOKEN` | Required for `discorduser` plugin |
| `TELEGRAM_BOT_TOKEN` | Optional Telegram bot token |
| `GITHUB_TOKEN` | GitHub personal access token |
| `CLICKUP_API_KEY` | ClickUp API key (also powers MCP server) |
| `BRAVE_API_KEY` | Brave Search API key |

### Step 5: Network Configuration

In Coolify, go to your OpenClaw service > **Settings**.

- Enable **Connect to Predefined Network** if your Hindsight service is in another Coolify stack.
- The compose file declares `rag-network` as external — this must match the network your Hindsight stack uses.
- If the Hindsight stack creates a network with a UUID suffix, update the compose file's `networks.rag-network` name or use Coolify's custom network name feature.

### Step 6: Deploy

Click **Deploy** in the Coolify UI. The build order is automatic:

1. Coolify builds both Dockerfile targets from `docker/Dockerfile`
2. `volume-init` runs, ensures volume permissions (uid 1000)
3. `sandbox-builder` starts, tags the sandbox image as `openclaw-sandbox:bookworm-slim`, exits
4. `docker-proxy` starts (socket proxy, internal network only)
5. `openclaw` gateway starts with `DOCKER_HOST=tcp://docker-proxy:2375`

First build will take several minutes (upstream OpenClaw source build + CLI installations). Subsequent builds use Docker layer cache and are much faster.

### Step 7: First-Boot Config Generation

On the first deploy, the entrypoint automatically generates `openclaw.json` from the baked-in template using the environment variables you set in Step 4. **No manual config file placement needed.**

Important: regeneration happens only when `~/.openclaw/openclaw.json` does not exist. If you change template/env values later (for example `BRAIN_HOST_PATH`), delete `~/.openclaw/openclaw.json` and redeploy to regenerate.

The entrypoint also copies `mcporter.json` to the persistent volume. All MCP servers (hindsight, zai-vision, web-reader, zread, clickup) are pre-configured and work immediately when their corresponding API key env vars are set.

To verify the generated config:
1. Go to Coolify > your OpenClaw service > select `openclaw` container > **Terminal**
2. Run: `cat /home/node/.openclaw/openclaw.json`
3. Verify the template variables were substituted correctly

To customize further (add channel bindings, more agents, plugins, etc.), edit the config via Coolify Terminal or use `openclaw config.patch`.

### Step 8: Set the Brain Host Path

After the first deploy, you need to determine the actual Coolify volume name and set `BRAIN_HOST_PATH`:

1. From SSH on the Docker host (or Coolify host terminal, not the `openclaw` container):
   ```bash
   docker volume ls | grep openclaw
   ```
2. Note the brain volume name (e.g., `x0kgwssswogs0os8ggsko8s0_openclaw-brain`)
3. Set the env var in Coolify:
   ```
   BRAIN_HOST_PATH=/var/lib/docker/volumes/x0kgwssswogs0os8ggsko8s0_openclaw-brain/_data
   ```
4. Update the config: either delete `openclaw.json` from the volume and redeploy (triggers regeneration), or edit the workspace path directly in the config file.

See [dood-path-mapping.md](dood-path-mapping.md) for the full details.

---

## Verification

All verification steps use **Coolify Terminal** (service > container > Terminal) or **Coolify Logs**.

### Check via Coolify Terminal

Open a terminal on the `openclaw` container:

```bash
# Check sandbox configuration for all agents
openclaw sandbox explain

# Check specific agents
openclaw sandbox explain --agent main       # Expected: mode off
openclaw sandbox explain --agent gregailia  # Expected: mode all, workspace rw

# Verify Docker API connectivity (via proxy)
curl -s http://docker-proxy:2375/version | head -1
# Should return JSON with Docker version

# Run the doctor
openclaw doctor --fix

# List sandbox containers (empty initially)
openclaw sandbox list

# Test sandbox creation (sends message to a sandboxed agent)
openclaw agent --agent gregailia --message "health check"

# Verify sandbox container was created
openclaw sandbox list
```

### Check via Coolify Logs

In Coolify UI, check the logs for each service:

- **volume-init**: Should show `chown` commands and exit cleanly
- **sandbox-builder**: Should show `sandbox image ready` and exit cleanly
- **docker-proxy**: Should show HAProxy startup, no errors
- **openclaw**: Should show config generation (first boot) and gateway startup

### Verify network isolation

From the `openclaw` container terminal:

```bash
# Verify proxy BLOCKS dangerous endpoints (should return 403 or connection refused)
curl -sf http://docker-proxy:2375/volumes 2>&1 || echo "BLOCKED (expected)"
curl -sf http://docker-proxy:2375/swarm 2>&1 || echo "BLOCKED (expected)"

# Verify proxy ALLOWS container endpoints
curl -s http://docker-proxy:2375/containers/json | head -1
# Should return JSON array
```

---

## Gotchas and Lessons Learned

These are hard-won lessons from production debugging. Read them before troubleshooting.

### 1. Sandboxed workspace paths must be HOST-absolute

The `workspace` field in `agents.list[]` for sandboxed agents must point to the **host filesystem** path, not the container-internal path. See [dood-path-mapping.md](dood-path-mapping.md).

### 2. Do NOT add explicit sandbox binds for /workspace

OpenClaw handles the workspace mount via `workspaceAccess`. Adding a manual `sandbox.docker.binds` entry for `/workspace` creates a duplicate mount conflict. See [dood-path-mapping.md](dood-path-mapping.md#the-mount-conflict-do-not-use-explicit-binds).

### 3. Coolify ignores volume name: directives

Even with `name: openclaw_config` in compose, Coolify prepends its resource UUID. The actual volume name is `<UUID>_openclaw-config`. Always verify with `docker volume ls`.

### 4. OHO must be installed via npx, not globally

`oh-my-opencode` v3.x has a Commander.js bug when installed globally via npm. Always use:
```bash
npx -y oh-my-opencode install
```
The `bootstrap-opencode.sh` script handles this correctly.

### 5. Docker CLI access = host access

The Docker CLI binary is included in the gateway image for sandbox management. Non-sandboxed agents with `exec` permission can use it to run arbitrary Docker commands on the host. This is the DooD trust trade-off. See [security-model.md](security-model.md).

### 6. The real protection is agent-level, not infra-level

The socket proxy is defense-in-depth, not the primary boundary. The actual protection is: **sandbox untrusted agents** (`"sandbox": { "mode": "all" }`) and **restrict `exec` on non-sandboxed agents** (`"tools": { "deny": ["exec", "process"] }`). See [security-model.md](security-model.md#the-real-protection) for the full model.

---

## Local Development with Agent Brains

For local dev, agent brain repositories are **bind-mounted** as writable workspaces. This lets agents read/write brain files and git commit/push, with changes syncing instantly between host and container.

### Directory Layout

```
your-project/
├── brain-core/              ← this repo (Docker image source)
│   └── docker/
│       └── docker-compose.dev.yml
└── {org}-brain/             ← agent brain repo (separate git repo)
    ├── agents/
    │   ├── {admin-agent}/
    │   └── my-agent/
    ├── knowledge/
    └── config/
        └── openclaw.json.template   ← brain-specific config template
```

### How It Works

`docker-compose.dev.yml` bind-mounts the brain repo to `/opt/brain` inside the container. Each agent's `workspace` in `openclaw.json` points to its subdirectory (e.g., `/opt/brain/agents/{admin-agent}`).

The brain repo can ship its own `config/openclaw.json.template` with pre-configured agents. Set `OPENCLAW_CONFIG_TEMPLATE` to use it on first boot:

```bash
OPENCLAW_CONFIG_TEMPLATE=/opt/brain/config/openclaw.json.template
```

### Setup

1. Clone both repos as siblings:
   ```bash
   git clone <brain-core-url> brain-core
   git clone <brain-workspace-url> {org}-brain
   ```

2. Configure `.env`:
    ```bash
    cd brain-core
    cp .env.example .env
    # Edit .env — set OPENCLAW_GATEWAY_TOKEN + API keys
    # Set BRAIN_HOST_PATH to the absolute path of your brain repo
    # OPENCLAW_CONFIG_TEMPLATE defaults to /opt/brain/config/openclaw.json.template
    ```

3. Start the stack:
   ```bash
   make up
   ```

4. On first boot, the entrypoint generates `openclaw.json` from the brain repo's template.

### Custom Brain Path

Set `BRAIN_HOST_PATH` in `.env` to the absolute path of your brain repo:

```bash
BRAIN_HOST_PATH=/absolute/path/to/your-brain-repo
```

### Using the Generic Template

To use brain-core's built-in single-agent template instead of the brain repo's template:

```bash
OPENCLAW_CONFIG_TEMPLATE=/opt/config/openclaw.json.template
```

### Git Operations from Inside the Container

Agents can git commit/push from inside the container because the workspace is a bind-mounted git repo. The `GITHUB_TOKEN` env var is already available for HTTPS auth. For SSH-based auth, add an SSH key bind mount to the compose file.

### Sandboxed Agents (DooD)

For sandboxed agents in local dev, the `workspace` must be a **host-absolute path** (not a container path) because sandbox containers are DooD siblings. Set per-agent workspace overrides in `openclaw.json` after first boot:

```json
{
  "id": "my-agent",
  "workspace": "/Users/you/path/to/{org}-brain/agents/my-agent",
  "sandbox": { "mode": "all", "scope": "agent", "workspaceAccess": "rw" }
}
```

See [dood-path-mapping.md](dood-path-mapping.md) for the full path resolution model.

---

## Rollback

### Quick rollback (disable sandbox only)

In Coolify Terminal on the `openclaw` container:

1. Edit `~/.openclaw/openclaw.json`
2. Remove the `"sandbox"` key from `agents.defaults`
3. All agents fall back to `sandbox.mode: "off"`
4. Restart the service via Coolify UI

Or: remove the `DOCKER_HOST` env var from Coolify Environment Variables and redeploy. The gateway won't connect to the proxy and sandbox features won't activate.

### Full rollback (revert to previous compose)

1. In your Git repo, revert `docker-compose.coolify.yml` to the previous version
2. Push to the branch Coolify tracks
3. Redeploy via Coolify UI

### Cleanup sandbox containers

From Coolify Terminal on the `openclaw` container:

```bash
# Remove all sandbox containers gracefully
openclaw sandbox recreate --all --force
```

---

## Troubleshooting

| Problem | Check via Coolify | Fix |
|---------|-------------------|-----|
| Build fails | Coolify build logs | Check `docker/Dockerfile` exists, verify build args in env vars |
| Config not generated | Terminal: `ls ~/.openclaw/openclaw.json` | Check template exists at `/opt/config/`, verify env vars are set |
| Gateway can't reach docker-proxy | Terminal: `curl http://docker-proxy:2375/version` | Check both services are running, verify `openclaw-internal` network |
| Sandbox container not created | Terminal: `openclaw sandbox explain --agent <id>` | Verify sandbox mode is not `off`, check image exists |
| Sandbox can't see workspace files | Terminal: check agent workspace path | DooD path mapping issue — see [dood-path-mapping.md](dood-path-mapping.md) |
| Duplicate mount error | Coolify logs for sandbox errors | Remove explicit `sandbox.docker.binds` for `/workspace` |
| Sandbox can't reach Hindsight | Terminal (in sandbox): `curl http://hindsight:8888` | Verify sandbox network is `rag-network`, check Hindsight is running |
| Permission denied in sandbox | Coolify logs for sandbox errors | Check volume-init ran; directories owned by uid 1000 |
| Image not found | Coolify logs: `openclaw-sandbox:bookworm-slim` | Check sandbox-builder ran successfully |
| Proxy returns 403 | Terminal: `curl http://docker-proxy:2375/<endpoint>` | Endpoint not enabled; check docker-proxy environment vars |
| Env var not set | Coolify Environment Variables page | Coolify auto-detects from compose; set missing values |
| OHO install fails | Check bootstrap-opencode.sh output | Must use `npx -y oh-my-opencode install`, not global npm install |
