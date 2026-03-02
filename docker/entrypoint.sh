#!/bin/sh
# =============================================================================
# OpenClaw Gateway Entrypoint — brain-core
#
# Handles runtime concerns in order:
#   1. Brain repo sync (git clone/pull when BRAIN_GIT_REPO is set)
#   2. First-boot config generation (envsubst from template)
#   3. mcporter.json provisioning
#   4. OpenCode bootstrap + server (required by orchestration scripts)
#   5. Hook script execution (user-defined startup logic)
#   6. Config self-heal (openclaw doctor --fix)
#   7. Periodic config self-heal (background, every OPENCLAW_DOCTOR_INTERVAL seconds)
#   8. Auto-pair device via loopback (background, after gateway starts)
#   9. Sandbox browser CDP host patch (macOS Docker Desktop workaround)
#  10. Gateway exec (replaces this shell — PID 1 via docker-init)
#
# All tool installations are baked into the Docker image (see Dockerfile).
# Config templates are baked at /opt/config/.
# Set OPENCLAW_CONFIG_TEMPLATE to use an alternative template (e.g., from a brain workspace).
# =============================================================================
set -e

BRAIN_DIR="/opt/brain"
CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
TEMPLATE_FILE="${OPENCLAW_CONFIG_TEMPLATE:-/opt/config/openclaw.json.template}"
HOOKS_DIR="${OPENCLAW_HOOKS_DIR:-$CONFIG_DIR/hooks}"
OPENCODE_PORT="${OPENCODE_SERVER_PORT:-4096}"

# ---------------------------------------------------------------------------
# 1. Brain repo sync (git clone or pull)
#    When BRAIN_GIT_REPO is set, clones or updates the brain workspace at
#    /opt/brain from GitHub. Uses GITHUB_TOKEN for authentication.
#    Skipped in dev (where /opt/brain is a bind mount from the host).
#
#    Env vars:
#      BRAIN_GIT_REPO   — GitHub repo (e.g., "org/brain-repo"). Unset = skip.
#      BRAIN_GIT_BRANCH — Branch to track (default: main).
#      BRAIN_LIVE_BRANCH — Working branch for agents (default: live).
#                          Created from BRAIN_GIT_BRANCH if it doesn't exist on remote.
#                          Agents commit here; PRs go from live → main for human review.
#      GITHUB_TOKEN     — PAT or GitHub App token for private repos.
# ---------------------------------------------------------------------------
if [ -n "${BRAIN_GIT_REPO:-}" ]; then
  BRAIN_GIT_BRANCH="${BRAIN_GIT_BRANCH:-main}"

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "[entrypoint] ERROR: BRAIN_GIT_REPO is set but GITHUB_TOKEN is empty."
    echo "[entrypoint]        Set GITHUB_TOKEN to a PAT or GitHub App token for private repos."
    exit 1
  fi

  # Use GIT_ASKPASS for secure token handling (token never embedded in URL or .git/config)
  CLONE_URL="https://github.com/${BRAIN_GIT_REPO}.git"
  trap 'rm -f "$GIT_ASKPASS_HELPER" 2>/dev/null' EXIT
  
  # Create temporary GIT_ASKPASS helper script
  GIT_ASKPASS_HELPER=$(mktemp)
  printf '#!/bin/sh\necho "%s"\n' "$GITHUB_TOKEN" > "$GIT_ASKPASS_HELPER"
  chmod +x "$GIT_ASKPASS_HELPER"

  if [ -d "$BRAIN_DIR/.git" ]; then
    echo "[entrypoint] Pulling brain repo (${BRAIN_GIT_REPO}@${BRAIN_GIT_BRANCH})..."
    GIT_ASKPASS="$GIT_ASKPASS_HELPER" git -C "$BRAIN_DIR" fetch origin "$BRAIN_GIT_BRANCH" --depth 1 2>&1
    git -C "$BRAIN_DIR" reset --hard "origin/$BRAIN_GIT_BRANCH" 2>&1
    echo "[entrypoint] Brain repo updated"
  else
    echo "[entrypoint] Cloning brain repo (${BRAIN_GIT_REPO}@${BRAIN_GIT_BRANCH})..."
    # Remove any stale contents (e.g., empty volume mount)
    rm -rf "${BRAIN_DIR:?}"/*
    GIT_ASKPASS="$GIT_ASKPASS_HELPER" git clone --depth 1 --branch "$BRAIN_GIT_BRANCH" "$CLONE_URL" "$BRAIN_DIR" 2>&1
    echo "[entrypoint] Brain repo cloned to $BRAIN_DIR"
  fi
  
  # Checkout live working branch for agent operations
  BRAIN_LIVE_BRANCH="${BRAIN_LIVE_BRANCH:-live}"
  if [ "$BRAIN_LIVE_BRANCH" != "$BRAIN_GIT_BRANCH" ]; then
    GIT_ASKPASS="$GIT_ASKPASS_HELPER" git -C "$BRAIN_DIR" fetch origin "$BRAIN_LIVE_BRANCH" --depth 1 2>/dev/null || true

    if git -C "$BRAIN_DIR" rev-parse --verify "origin/$BRAIN_LIVE_BRANCH" >/dev/null 2>&1; then
      git -C "$BRAIN_DIR" checkout -B "$BRAIN_LIVE_BRANCH" "origin/$BRAIN_LIVE_BRANCH" 2>&1
      echo "[entrypoint] Checked out live branch '$BRAIN_LIVE_BRANCH' (from remote)"
    else
      git -C "$BRAIN_DIR" checkout -b "$BRAIN_LIVE_BRANCH" 2>&1
      echo "[entrypoint] Created live branch '$BRAIN_LIVE_BRANCH' (from $BRAIN_GIT_BRANCH)"
    fi
  fi

  # Git identity for agent backup commits
  git -C "$BRAIN_DIR" config user.name "${BRAIN_GIT_USER:-openclaw-bot}"
  git -C "$BRAIN_DIR" config user.email "${BRAIN_GIT_EMAIL:-bot@openclaw.local}"

  # Persistent credentials so agents can push during heartbeat backups
  git -C "$BRAIN_DIR" config credential.helper 'store'
  printf 'https://x-access-token:%s@github.com\n' "$GITHUB_TOKEN" > /home/node/.git-credentials
  chmod 600 /home/node/.git-credentials

  # Clean up temporary helper
  rm -f "$GIT_ASKPASS_HELPER"
else
  echo "[entrypoint] BRAIN_GIT_REPO not set, skipping brain sync (dev bind-mount assumed)"
fi

# ---------------------------------------------------------------------------
# 1b. Sandbox path alias
#     Sandboxed agents use BRAIN_HOST_PATH (host-absolute) as their workspace
#     so sandbox containers can mount it. Create a symlink inside the gateway
#     so the gateway's skill scanner can also resolve these paths.
# ---------------------------------------------------------------------------
MEDIA_BRAIN="$CONFIG_DIR/media/brain"
if [ -n "${BRAIN_HOST_PATH:-}" ] && [ "$BRAIN_HOST_PATH" != "$BRAIN_DIR" ]; then
  # Safety: reject dangerous system paths before any modification
  case "$BRAIN_HOST_PATH" in
    /|/bin|/boot|/dev|/etc|/lib|/lib64|/proc|/run|/sbin|/sys|/usr|/var|/opt|/home|/root|/tmp)
      echo "[entrypoint] ERROR: BRAIN_HOST_PATH='$BRAIN_HOST_PATH' is a system path. Refusing to modify."
      exit 1
      ;;
  esac
  # Prefer routing through ~/.openclaw/media/brain/ when mounted (writable).
  # This satisfies OpenClaw's media-upload allowed-root check which requires
  # file paths to resolve under ~/.openclaw/media/.
  if [ -d "$MEDIA_BRAIN" ]; then
    SYMLINK_TARGET="$MEDIA_BRAIN"
  else
    SYMLINK_TARGET="$BRAIN_DIR"
  fi
  if [ -L "$BRAIN_HOST_PATH" ]; then
    # Already a symlink — safe to replace if target changed
    if [ "$(readlink "$BRAIN_HOST_PATH")" != "$SYMLINK_TARGET" ]; then
      rm "$BRAIN_HOST_PATH"
      ln -s "$SYMLINK_TARGET" "$BRAIN_HOST_PATH"
      echo "[entrypoint] Symlinked $BRAIN_HOST_PATH -> $SYMLINK_TARGET (sandbox path resolution)"
    fi
  elif [ -d "$BRAIN_HOST_PATH" ] && [ -z "$(ls -A "$BRAIN_HOST_PATH" 2>/dev/null)" ]; then
    # Empty directory (common: stale volume mount / ghost dir) — safe to replace
    rmdir "$BRAIN_HOST_PATH"
    if mkdir -p "$(dirname "$BRAIN_HOST_PATH")" 2>/dev/null; then
      ln -s "$SYMLINK_TARGET" "$BRAIN_HOST_PATH"
      echo "[entrypoint] Replaced empty dir $BRAIN_HOST_PATH with symlink -> $SYMLINK_TARGET"
    else
      echo "[entrypoint] WARNING: Cannot create parent dirs for $BRAIN_HOST_PATH (permission denied). Skipping sandbox path alias."
    fi
  elif [ -e "$BRAIN_HOST_PATH" ]; then
    # Non-empty file/directory — refuse to delete (could be a bind mount or real data)
    echo "[entrypoint] WARNING: $BRAIN_HOST_PATH exists and is not a symlink — skipping sandbox path alias."
    echo "[entrypoint]          Sandbox skill resolution may fail. Remove it manually or adjust BRAIN_HOST_PATH."
  else
    # Nothing exists — safe to create
    if mkdir -p "$(dirname "$BRAIN_HOST_PATH")" 2>/dev/null; then
      ln -s "$SYMLINK_TARGET" "$BRAIN_HOST_PATH"
      echo "[entrypoint] Symlinked $BRAIN_HOST_PATH -> $SYMLINK_TARGET (sandbox path resolution)"
    else
      echo "[entrypoint] WARNING: Cannot create parent dirs for $BRAIN_HOST_PATH (permission denied). Skipping sandbox path alias."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 2. First-boot config generation (envsubst)
# ---------------------------------------------------------------------------
BAKED_TEMPLATE="/opt/config/openclaw.json.template"

if [ ! -f "$CONFIG_FILE" ]; then
  # Resolve template: prefer configured path, fall back to baked-in generic.
  if [ -f "$TEMPLATE_FILE" ]; then
    ACTIVE_TEMPLATE="$TEMPLATE_FILE"
  elif [ "$TEMPLATE_FILE" != "$BAKED_TEMPLATE" ] && [ -f "$BAKED_TEMPLATE" ]; then
    echo "[entrypoint] WARNING: Template not found at $TEMPLATE_FILE — falling back to $BAKED_TEMPLATE"
    ACTIVE_TEMPLATE="$BAKED_TEMPLATE"
  else
    ACTIVE_TEMPLATE=""
  fi

  if [ -n "$ACTIVE_TEMPLATE" ]; then
    echo "[entrypoint] First boot — generating openclaw.json from $(basename "$ACTIVE_TEMPLATE")"
    ENVSUBST_VARS='$OPENCLAW_GATEWAY_TOKEN $OPENCLAW_DEFAULT_MODEL $OPENCLAW_USER_TIMEZONE $OPENCLAW_AGENT_NAME $OPENCLAW_ADMIN_DISCORD_ID $OPENCLAW_ADMIN_TELEGRAM_ID $TELEGRAM_API_ID $TELEGRAM_API_HASH $TELEGRAM_STRING_SESSION $GOOGLE_WORKSPACE_CLIENT_ID $GOOGLE_WORKSPACE_CLIENT_SECRET $GOOGLE_WORKSPACE_EMAIL $CLICKUP_API_KEY $ZAI_API_KEY $DISCORD_USER_TOKEN $BRAIN_HOST_PATH'
    for var in $(env | grep '^DISCORD_BOT_TOKEN_[0-9]' | cut -d= -f1); do
      ENVSUBST_VARS="$ENVSUBST_VARS \$$var"
    done
    envsubst "$ENVSUBST_VARS" < "$ACTIVE_TEMPLATE" > "$CONFIG_FILE"

    if ! jq . "$CONFIG_FILE" > /dev/null 2>&1; then
      echo "[entrypoint] ERROR: Generated config is not valid JSON. Template substitution may have failed."
      echo "[entrypoint]        Check that all env vars referenced in the template are set."
      rm -f "$CONFIG_FILE"
      exit 1
    fi

    # Warn if BRAIN_HOST_PATH is empty but config references sandbox workspaces
    if [ -z "${BRAIN_HOST_PATH:-}" ] && grep -q 'BRAIN_HOST_PATH' "$ACTIVE_TEMPLATE" 2>/dev/null; then
      echo "[entrypoint] WARNING: BRAIN_HOST_PATH is empty but config template references it."
      echo "[entrypoint]          Sandbox agent workspace paths will be invalid."
    fi

    echo "[entrypoint] Config generated at $CONFIG_FILE"

    # Clean device pairing state on first boot so the gateway auto-approves
    # loopback connections (required for the managed browser tool to work).
    DEVICES_DIR="$CONFIG_DIR/devices"
    mkdir -p "$DEVICES_DIR"
    echo '{}' > "$DEVICES_DIR/paired.json"
    echo '{}' > "$DEVICES_DIR/pending.json"
    echo "[entrypoint] Device pairing state reset (first boot)"
  else
    echo "[entrypoint] WARNING: No config and no template found. Gateway will start with --allow-unconfigured."
  fi
else
  echo "[entrypoint] Existing config found, skipping generation"
fi

# ---------------------------------------------------------------------------
# 3. mcporter.json provisioning
# ---------------------------------------------------------------------------
MCPORTER_DIR="/home/node/.mcporter"
if [ ! -f "$MCPORTER_DIR/mcporter.json" ] && [ -f /opt/config/mcporter.json ]; then
  mkdir -p "$MCPORTER_DIR"
  cp /opt/config/mcporter.json "$MCPORTER_DIR/mcporter.json"
  echo "[entrypoint] mcporter.json provisioned to $MCPORTER_DIR"
fi

# ---------------------------------------------------------------------------
# 3b. Plugin dependency install
#     Plugins may have npm dependencies (package.json) that need installing.
#     In dev, plugins are bind-mounted without node_modules. In production,
#     plugins on the persistent volume may also lack dependencies.
# ---------------------------------------------------------------------------
for plugin_dir in "$CONFIG_DIR"/extensions/*/; do
  [ -f "$plugin_dir/package.json" ] || continue
  [ -d "$plugin_dir/node_modules" ] && continue
  plugin_name=$(basename "$plugin_dir")
  echo "[entrypoint] Installing dependencies for plugin $plugin_name..."
  (cd "$plugin_dir" && npm install --production 2>&1) || echo "[entrypoint] WARNING: Plugin $plugin_name dependency install failed (non-fatal)"
done

# ---------------------------------------------------------------------------
# 4. OpenCode bootstrap + server
# ---------------------------------------------------------------------------
BOOTSTRAP="/opt/scripts/bootstrap-opencode.sh"
BOOTSTRAP_TIMEOUT="${OPENCODE_BOOTSTRAP_TIMEOUT:-180}"
if [ -f "$BOOTSTRAP" ]; then
  echo "[entrypoint] Running OpenCode bootstrap (timeout: ${BOOTSTRAP_TIMEOUT}s)..."
  if command -v timeout >/dev/null 2>&1; then
    timeout "$BOOTSTRAP_TIMEOUT" sh "$BOOTSTRAP" || echo "[entrypoint] WARNING: OpenCode bootstrap failed or timed out (non-fatal)"
  else
    sh "$BOOTSTRAP" || echo "[entrypoint] WARNING: OpenCode bootstrap failed (non-fatal)"
  fi
fi

echo "[entrypoint] Starting OpenCode server on port $OPENCODE_PORT..."
(cd /opt/opencode && opencode serve \
  --port "$OPENCODE_PORT" --hostname 127.0.0.1) &
OPENCODE_PID=$!

# Wait for readiness
OPENCODE_READY=0
for i in $(seq 1 30); do
  if curl -sf --max-time 2 "http://127.0.0.1:${OPENCODE_PORT}/session" >/dev/null 2>&1; then
    OPENCODE_READY=1
    break
  fi
  sleep 1
done

if [ "$OPENCODE_READY" = "1" ]; then
  echo "[entrypoint] OpenCode server ready (PID $OPENCODE_PID, port $OPENCODE_PORT)"
else
  echo "[entrypoint] WARNING: OpenCode server did not become ready within 30s (PID $OPENCODE_PID)"
fi

# ---------------------------------------------------------------------------
# 5. Hook scripts
# ---------------------------------------------------------------------------
if [ -d "$HOOKS_DIR" ]; then
  for hook in "$HOOKS_DIR"/*.sh; do
    [ -f "$hook" ] || continue
    echo "[entrypoint] Running hook: $(basename "$hook")"
    sh "$hook" || echo "[entrypoint] Hook $(basename "$hook") failed (non-fatal, continuing)"
  done
else
  echo "[entrypoint] No hooks directory at $HOOKS_DIR, skipping hooks"
fi

# ---------------------------------------------------------------------------
# 6. Config self-heal (openclaw doctor --fix)
# ---------------------------------------------------------------------------
# Pre-create dirs that doctor expects (avoids CRITICAL warnings)
mkdir -p "$CONFIG_DIR/agents/main/sessions" "$CONFIG_DIR/credentials" 2>/dev/null || true
chmod 700 "$CONFIG_DIR" 2>/dev/null || true

if [ -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] Running config doctor..."
  node /app/dist/index.js doctor --fix --non-interactive 2>&1 || echo "[entrypoint] WARNING: doctor failed (non-fatal)"
fi

# ---------------------------------------------------------------------------
# 7. Periodic config self-heal (background)
# ---------------------------------------------------------------------------
DOCTOR_INTERVAL="${OPENCLAW_DOCTOR_INTERVAL:-300}"
if [ "$DOCTOR_INTERVAL" -gt 0 ] 2>/dev/null; then
  (
    while true; do
      sleep "$DOCTOR_INTERVAL"
      node /app/dist/index.js doctor --fix --non-interactive >/dev/null 2>&1 || true
    done
  ) &
  echo "[entrypoint] Config doctor scheduled every ${DOCTOR_INTERVAL}s (PID $!)"
fi

# ---------------------------------------------------------------------------
# 8. Auto-pair device via loopback (background, after gateway starts)
# ---------------------------------------------------------------------------
GW_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GW_TOKEN=""
if [ -f "$CONFIG_FILE" ]; then
  GW_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null) || true
fi
if [ -n "$GW_TOKEN" ]; then
  (
    paired=false
    for i in $(seq 1 30); do
      if node /app/dist/index.js browser profiles \
           --url "ws://127.0.0.1:${GW_PORT}" --token "$GW_TOKEN" \
           >/dev/null 2>&1; then
        echo "[entrypoint] Device auto-paired via loopback"
        paired=true
        break
      fi
      sleep 2
    done
    if [ "$paired" = false ]; then
      echo "[entrypoint] WARNING: Device auto-pairing failed after 60s (gateway may not be ready)"
    fi
  ) &
fi
# ---------------------------------------------------------------------------
# 9. Sandbox browser CDP host patch (macOS Docker Desktop workaround)
#    On macOS Docker Desktop, network_mode:host gives the gateway the Linux
#    VM's network — not the macOS host's network. Sandbox browser containers
#    publish their CDP port to the macOS host (127.0.0.1:random), but the
#    gateway VM cannot reach 127.0.0.1:random. It CAN reach those ports via
#    the Docker Desktop host-gateway IP (typically 192.168.65.254).
#
#    This patches ONLY the CDP connection parameters in the sandbox bundle:
#      - waitForSandboxCdp health check URL
#      - buildSandboxBrowserResolvedConfig cdpHost + cdpIsLoopback
#    The bridge server's own bind address (127.0.0.1) is NOT touched,
#    preserving the loopback auth requirement.
#
#    Detection: Docker Desktop VMs use LinuxKit kernels. Native Linux hosts
#    do NOT need this patch (127.0.0.1 works natively with network_mode:host).
#    On native Linux, host.docker.internal may still resolve (modern Docker
#    adds it by default), but patching would BREAK connectivity because
#    published ports are only reachable on 127.0.0.1, not the gateway IP.
#    Override with OPENCLAW_CDP_PATCH=force|skip to bypass auto-detection.
# ---------------------------------------------------------------------------
NEEDS_CDP_PATCH=false
case "${OPENCLAW_CDP_PATCH:-auto}" in
  force) NEEDS_CDP_PATCH=true ;;
  skip)  NEEDS_CDP_PATCH=false ;;
  *)
    # Auto-detect: Docker Desktop VM kernel contains "linuxkit" or "docker-desktop"
    if uname -r 2>/dev/null | grep -qiE 'linuxkit|docker-desktop'; then
      NEEDS_CDP_PATCH=true
    fi
    ;;
esac

if [ "$NEEDS_CDP_PATCH" = "true" ]; then
  # Resolve host-gateway IP (IPv4 only — Chrome CDP rejects hostnames and IPv6)
  CDP_HOST=$(getent hosts host.docker.internal 2>/dev/null | awk '{print $1}' | head -1)
  case "$CDP_HOST" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*)
      ;; # Valid IPv4
    *)
      echo "[entrypoint] WARNING: host.docker.internal resolved to '$CDP_HOST' (expected IPv4) — skipping CDP patch"
      CDP_HOST=""
      ;;
  esac

  if [ -n "$CDP_HOST" ]; then
    patched=0
    for bundle in /app/dist/sandbox-*.js; do
      [ -f "$bundle" ] || continue
      # Skip CLI helper bundles (sandbox-cli-*.js)
      case "$bundle" in *-cli-*) continue ;; esac

      if grep -q 'cdpHost: "127.0.0.1"' "$bundle" 2>/dev/null; then
        sed -i \
          -e 's|http://127\.0\.0\.1:\${params\.cdpPort}/json/version|http://'"$CDP_HOST"':${params.cdpPort}/json/version|g' \
          -e 's|cdpHost: "127\.0\.0\.1"|cdpHost: "'"$CDP_HOST"'"|g' \
          -e 's|cdpIsLoopback: true|cdpIsLoopback: false|g' \
          -e 's|did not become reachable on 127\.0\.0\.1:|did not become reachable on '"$CDP_HOST"':|g' \
          "$bundle"
        patched=$((patched + 1))
      fi
    done
    if [ "$patched" -gt 0 ]; then
      echo "[entrypoint] Sandbox browser CDP host patched to $CDP_HOST ($patched bundle(s))"
    else
      echo "[entrypoint] WARNING: CDP patch expected (Docker Desktop detected) but no sandbox bundles matched."
      echo "[entrypoint]          Sandbox browser may not work. Check /app/dist/sandbox-*.js for cdpHost patterns."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 10. Gateway exec
# ---------------------------------------------------------------------------
GATEWAY_ARGS="--bind ${OPENCLAW_GATEWAY_BIND:-lan} --port $GW_PORT"
if [ ! -f "$CONFIG_FILE" ] || ! jq . "$CONFIG_FILE" > /dev/null 2>&1; then
  echo "[entrypoint] No valid config — starting with --allow-unconfigured"
  GATEWAY_ARGS="$GATEWAY_ARGS --allow-unconfigured"
fi
exec node /app/dist/index.js gateway $GATEWAY_ARGS
