# Security Model

Trust boundaries, network isolation, and the DooD trade-off for OpenClaw gateway deployments.

---

## Architecture Overview

```
Docker Compose Stack (Coolify-managed)
├── openclaw-gateway          ← main process, Docker CLI in image
│     ├── rag-network         ← talks to Hindsight, sandbox containers
│     └── openclaw-internal   ← talks to docker-proxy
├── docker-proxy              ← filtered Docker API (tecnativa/docker-socket-proxy)
│     └── openclaw-internal   ← only reachable by gateway
├── sandbox-builder           ← builds sandbox image, exits
└── workspace-init            ← volume permissions, exits

Spawned outside compose (DooD siblings on host Docker):
└── openclaw-sbx-*            ← sandbox containers, rag-network only
```

---

## The DooD Trust Trade-off

The gateway container includes the **Docker CLI binary** and connects to the host Docker daemon via the socket proxy (`DOCKER_HOST=tcp://docker-proxy:2375`). This is required for sandbox container lifecycle management (create, start, stop, exec, inspect).

**What the gateway can do:**
- Create, start, stop, and remove containers on the host
- Execute commands inside any running container
- Pull and list images
- Manage networks

**What the gateway cannot do (blocked by proxy):**
- Access volumes, secrets, swarm, nodes
- Build images via the API (builds happen at deploy time, not runtime)
- Authenticate or manage plugins

This means the gateway process — and any non-sandboxed agent with `exec` permission running inside it — has **significant control over the host Docker daemon**. This is the fundamental DooD trade-off.

---

## Docker Socket Proxy

The [tecnativa/docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) filters Docker API endpoints.

### Allowed Endpoints

| Endpoint | Reason |
|---|---|
| `CONTAINERS` | Sandbox lifecycle (create, start, stop, inspect, remove) |
| `EXEC` | Execute commands in sandbox containers |
| `IMAGES` | List and inspect images (sandbox image verification) |
| `NETWORKS` | Connect sandbox containers to rag-network |
| `POST` | Required for all write operations (create, exec, etc.) |

### Blocked Endpoints

| Endpoint | Risk if exposed |
|---|---|
| `VOLUMES` | Could mount arbitrary host paths |
| `SWARM` | Cluster-level operations |
| `SECRETS` | Docker secrets access |
| `NODES` | Cluster node management |
| `BUILD` | Build arbitrary images at runtime |
| `COMMIT` | Create images from containers |
| `AUTH` | Registry authentication |
| `PLUGINS` | Docker plugin management |
| `SYSTEM` | System-level info and events |

**Note:** Even with the proxy filtering endpoints, the gateway can still **stop or remove any host container** it can see. The proxy filters API categories, not per-container access. This is a known limitation of the socket proxy approach.

---

## Network Isolation

```
                    ┌─────────────────────────────────────────────┐
                    │              openclaw-internal               │
                    │  (bridge, internal — no egress to internet) │
                    │                                             │
                    │   ┌──────────┐      ┌──────────────┐       │
                    │   │ gateway  │◄────▶│ docker-proxy │       │
                    │   └──────────┘      └──────────────┘       │
                    └─────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────┐
                    │                rag-network                   │
                    │  (external — connects to Hindsight stack)   │
                    │                                             │
                    │   ┌──────────┐      ┌──────────────┐       │
                    │   │ gateway  │      │  Hindsight   │       │
                    │   └──────────┘      └──────────────┘       │
                    │   ┌──────────┐      ┌──────────────┐       │
                    │   │ sbx-agent│      │  sbx-agent-2 │       │
                    │   └──────────┘      └──────────────┘       │
                    └─────────────────────────────────────────────┘
```

### Key Isolation Properties

| Component | openclaw-internal | rag-network | Internet |
|---|---|---|---|
| Gateway | Yes | Yes | Via rag-network |
| Docker Proxy | Yes | No | No |
| Sandbox containers | **No** | Yes | Via rag-network |
| Hindsight | No | Yes | No (typically) |

**Critical:** Sandbox containers are on `rag-network` only. They **cannot reach** `docker-proxy` because they are not on `openclaw-internal`. This means a compromised sandbox cannot interact with the Docker API.

---

## What Agents Can and Cannot Do

### Sandboxed Agents

Sandboxed agents run in isolated containers with:

| Capability | Status | Notes |
|---|---|---|
| Read/write workspace | Controlled | Via `workspaceAccess` (ro or rw) |
| Access Hindsight | Yes | Via rag-network |
| Access Docker API | **No** | Not on openclaw-internal network |
| Access other workspaces | **No** | Only their own workspace is mounted |
| Run arbitrary processes | Limited | `pidsLimit: 256`, `capDrop: ["ALL"]` |
| Use network | Limited | rag-network only (no direct internet unless rag-network routes it) |
| Escape container | **No** | Standard container isolation + capability drop |

### Non-Sandboxed Agents (Gateway-Internal)

Non-sandboxed agents run inside the gateway container. Their capabilities depend on their tool policy:

| Permission | With `exec` | Without `exec` |
|---|---|---|
| Read/write workspace | Yes | Yes |
| Run shell commands | **Yes** | No |
| Use Docker CLI | **Yes** (via DOCKER_HOST) | No |
| Manage host containers | **Yes** | No |
| Access Docker proxy | **Yes** (same network) | **Yes** (but no tool to use it) |
| Read environment vars | **Yes** (API keys, tokens) | Via tool access only |

**The Docker CLI binary is included in the gateway image.** A non-sandboxed agent with `exec` permission can run `docker ps`, `docker stop <container>`, or even `docker run` to spawn arbitrary containers on the host. This is the DooD trust trade-off.

---

## The Real Protection

The socket proxy is a **defense-in-depth** layer, not the primary security boundary. The real protection comes from:

1. **Sandbox untrusted agents.** Any agent that shouldn't have host-level access must run in a sandbox (`"sandbox": { "mode": "all" }`).

2. **Restrict `exec` on non-sandboxed agents.** If an agent doesn't need shell access, deny it:
   ```json
   { "tools": { "deny": ["exec", "process"] } }
   ```

3. **Use `elevated` tool gating.** Restrict dangerous operations to specific users:
   ```json
   {
     "tools": {
       "elevated": {
         "enabled": false,
         "allowFrom": { "discord": ["YOUR_USER_ID"] }
       }
     }
   }
   ```

4. **Container resource limits.** The default sandbox config should include:
   ```json
   {
     "sandbox": {
       "docker": {
         "capDrop": ["ALL"],
         "pidsLimit": 256,
         "memory": "1g"
       }
     }
   }
   ```

---

## Security Audit Checklist

Run these checks after deployment via Coolify Terminal on the gateway container.

### Docker Socket Proxy

```bash
# Should BLOCK (403 or error):
curl -sf http://docker-proxy:2375/volumes && echo "FAIL: volumes exposed" || echo "PASS: volumes blocked"
curl -sf http://docker-proxy:2375/swarm && echo "FAIL: swarm exposed" || echo "PASS: swarm blocked"
curl -sf http://docker-proxy:2375/secrets && echo "FAIL: secrets exposed" || echo "PASS: secrets blocked"

# Should ALLOW (200 with JSON):
curl -sf http://docker-proxy:2375/containers/json > /dev/null && echo "PASS: containers allowed" || echo "FAIL: containers blocked"
curl -sf http://docker-proxy:2375/images/json > /dev/null && echo "PASS: images allowed" || echo "FAIL: images blocked"
```

### Per-Agent Sandbox

```bash
# Check each agent's sandbox configuration
openclaw sandbox explain

# Verify specific agents
openclaw sandbox explain --agent main        # Expected: mode=off
openclaw sandbox explain --agent gregailia   # Expected: mode=all, workspaceAccess=rw
```

### General Security Posture

Check in `openclaw.json` or via `openclaw sandbox explain`:

- [ ] `tools.elevated.enabled` is `false`
- [ ] `tools.elevated.allowFrom` contains only authorized user IDs
- [ ] `agents.defaults.sandbox.docker.capDrop` is `["ALL"]`
- [ ] `agents.defaults.sandbox.docker.pidsLimit` is `256`
- [ ] `agents.defaults.sandbox.docker.memory` is `1g`
- [ ] No container runs with `--privileged`
- [ ] Sandboxed agents have `exec` and `process` denied in tool policy
- [ ] Non-sandboxed agents are intentionally trusted with host access
