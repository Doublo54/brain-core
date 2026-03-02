# DooD Workspace Path Mapping

How sandbox workspace paths work when OpenClaw runs as a Docker-outside-of-Docker (DooD) sibling on Coolify/Hetzner.

---

## The Problem

OpenClaw's sandbox containers are **DooD siblings** — they run on the host Docker daemon, not inside the gateway container. When OpenClaw creates a sandbox container, it mounts the agent's workspace using the `workspace` path from `agents.list[]` in `openclaw.json`.

The catch: the gateway sees this path through its own volume mounts (e.g., `/home/node/.openclaw/workspace`), but the sandbox container is created on the **host Docker**, which knows nothing about the gateway's internal mount points. The workspace path must resolve on the **host filesystem**.

```
Gateway Container                    Host Docker
┌────────────────────┐               ┌─────────────────────────────────┐
│ /home/node/.openclaw│──volume──────▶│ /var/lib/docker/volumes/        │
│                    │               │   <UUID>_openclaw-config/_data  │
└────────────────────┘               └─────────────────────────────────┘
                                              │
                                              ▼
                                     Sandbox Container
                                     ┌────────────────┐
                                     │ /workspace      │
                                     │ (bind mount)    │
                                     └────────────────┘
```

**Rule:** Sandboxed agent `workspace` paths in `openclaw.json` must be **HOST-absolute paths**, not container-internal paths.

---

## Coolify Volume Naming

Coolify prepends its resource UUID to all volume names, regardless of the `name:` directive in docker-compose.

| Compose declaration | Actual Docker volume name |
|---|---|
| `name: openclaw_config` | `<COOLIFY_UUID>_openclaw-config` |
| `name: opencode_workdir` | `<COOLIFY_UUID>_opencode-workdir` |

The `name:` directive is effectively **ignored** by Coolify. You must discover the actual volume name.

### Finding Your Coolify UUID

1. **Coolify UI:** Go to your resource page. The URL contains the UUID: `https://coolify.example.com/project/.../resource/<UUID>`
2. **SSH to host:** Run `docker volume ls | grep openclaw` — the UUID prefix is visible on every volume name.
3. **Coolify Terminal:** From the gateway container, run `echo $HOSTNAME` — Coolify often encodes the UUID in the container name.

---

## Host Path Formula

For a sandboxed agent whose workspace is inside the config volume:

```
/var/lib/docker/volumes/<COOLIFY_UUID>_openclaw-config/_data/workspace/agents/<agent-id>
```

For a sandboxed agent using the dedicated workspaces volume:

```
/var/lib/docker/volumes/<COOLIFY_UUID>_openclaw-agent-workspaces/_data/<agent-id>
```

### Example

If your Coolify UUID is `x0kgwssswogs0os8ggsko8s0` and your agent ID is `sandboxed`:

```json
{
  "id": "sandboxed",
  "name": "Sandboxed Agent",
  "workspace": "/var/lib/docker/volumes/x0kgwssswogs0os8ggsko8s0_openclaw-config/_data/workspace/agents/sandboxed",
  "sandbox": { "mode": "all", "scope": "agent", "workspaceAccess": "rw" }
}
```

Set this via the `BRAIN_HOST_PATH` environment variable, which the config template uses on first boot.

---

## The Mount Conflict (Do NOT Use Explicit Binds)

**Do NOT** add explicit `sandbox.docker.binds` mapping to `/workspace`:

```json
// WRONG — causes duplicate mount conflict
{
  "sandbox": {
    "docker": {
      "binds": ["/some/path:/workspace"]
    }
  }
}
```

OpenClaw already mounts the workspace to `/workspace` inside the sandbox via the `workspaceAccess` field. Adding a manual bind creates a **duplicate mount** that shadows or conflicts with OpenClaw's built-in mount.

**Correct approach:** Set the `workspace` field to the host-absolute path. OpenClaw handles the rest.

```json
// CORRECT — let OpenClaw handle the mount
{
  "workspace": "/var/lib/docker/volumes/<UUID>_openclaw-config/_data/workspace/agents/sandboxed",
  "sandbox": { "mode": "all", "scope": "agent", "workspaceAccess": "rw" }
}
```

---

## Non-Coolify Deployments

If you deploy with plain `docker-compose` (no Coolify), volume names are as declared in the compose file. The host path follows the standard Docker pattern:

```
/var/lib/docker/volumes/openclaw_config/_data/workspace/agents/<agent-id>
```

No UUID prefix — the `name:` directive works as expected outside Coolify.

---

## Verification

From the host (via SSH):

```bash
# List volumes to find the actual name
docker volume ls | grep openclaw

# Inspect the volume to confirm the mount point
docker volume inspect <actual-volume-name>

# Verify the workspace directory exists
ls /var/lib/docker/volumes/<actual-volume-name>/_data/workspace/agents/
```

From the gateway container (via Coolify Terminal):

```bash
# Check sandbox explanation for an agent
openclaw sandbox explain --agent sandboxed

# The output shows the resolved workspace path — verify it's a host path
```

---

## Quick Reference

| Concept | Value |
|---|---|
| Non-sandboxed agent workspace | `/home/node/.openclaw/workspace` (container-internal, fine) |
| Sandboxed agent workspace | `/var/lib/docker/volumes/<UUID>_openclaw-config/_data/...` (host-absolute, required) |
| Coolify volume name format | `<COOLIFY_UUID>_<volume-name-from-compose>` |
| Explicit sandbox.docker.binds | **Never** for `/workspace` — let OpenClaw handle it |
| Config template variable | `BRAIN_HOST_PATH` (set in env vars) |
