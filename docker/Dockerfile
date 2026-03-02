# =============================================================================
# OpenClaw Gateway + Sandbox — Multi-stage Dockerfile
#
# Targets:
#   gateway  — OpenClaw gateway with all CLIs (compose default)
#   sandbox  — Sandbox image for agent tool execution (shares full CLI toolchain)
#
# Both targets share the `base` stage so CLI tooling/runtime are identical.
#
# Build context: repo root (compose uses context: ..)
#
# Build examples:
#   docker build --target gateway -t openclaw-gateway:local -f docker/Dockerfile .
#   docker build --target sandbox -t openclaw-sandbox:bookworm-slim -f docker/Dockerfile .
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 0: Build OpenClaw from upstream source
# ---------------------------------------------------------------------------
ARG OPENCLAW_VERSION=v2026.2.15

FROM node:22-bookworm AS openclaw-build

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip && \
    rm -rf /var/lib/apt/lists/*

# Bun is required by the OpenClaw build system
# SECURITY: bun install script is dynamic and changes per release; SHA256 pinning
# is impractical. Using download-then-execute pattern with --fail (via -f flag)
# to avoid executing error pages. Review script on version bumps.
RUN curl -fsSL https://bun.sh/install -o /tmp/bun-install.sh && \
    bash /tmp/bun-install.sh && \
    rm /tmp/bun-install.sh
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_VERSION
RUN if [ -z "$OPENCLAW_VERSION" ]; then \
      echo "ERROR: OPENCLAW_VERSION is empty" >&2; \
      exit 1; \
    fi && \
    git clone --depth 1 --branch "$OPENCLAW_VERSION" \
      https://github.com/openclaw/openclaw.git . && \
    pnpm install --frozen-lockfile && \
    pnpm build && \
    pnpm ui:install && \
    pnpm ui:build

# ---------------------------------------------------------------------------
# Stage 1: Shared base-common — Node 22 + shared CLIs/runtime
#
# This layer is shared by both gateway and sandbox targets.
# All tool installations happen here at build time (no runtime installs).
# ---------------------------------------------------------------------------
FROM node:22-bookworm-slim AS base-common

# System dependencies (includes gettext-base for envsubst)
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git jq unzip ca-certificates gnupg wget bash gettext-base rsync \
      python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

# --- Chromium system dependencies (shared by gateway MCP + sandbox scripts) ---
RUN npx -y playwright-core install-deps chromium

# --- uv (Python package manager) — needed for Google Workspace MCP ---
# SECURITY: SHA256 checksums pinned per architecture. Update on version bump.
ARG UV_VERSION=0.10.3
ARG UV_SHA256_X86_64=c60b9956a0e6727f0ddd881c303a706c6408b2047f3a8fa4d1454a826338ccdc
ARG UV_SHA256_AARCH64=cce7d1e4c34e22955cd647b256409b6504f4ae72acf190a6f26189efefbc9a9d
RUN set -eux; \
    arch="$(uname -m)"; \
    case "${arch}" in \
      x86_64) uv_target="x86_64-unknown-linux-gnu"; uv_sha256="${UV_SHA256_X86_64}" ;; \
      aarch64|arm64) uv_target="aarch64-unknown-linux-gnu"; uv_sha256="${UV_SHA256_AARCH64}" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_target}.tar.gz" -o /tmp/uv.tar.gz && \
    echo "${uv_sha256}  /tmp/uv.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/uv.tar.gz --strip-components=1 -C /usr/local/bin && \
    rm /tmp/uv.tar.gz

# --- npm-based CLIs ---
# oh-my-opencode is NOT installed globally — it's run via npx at first boot
# (see scripts/bootstrap-opencode.sh). This avoids the Commander.js bug
# in the globally-installed Bun shim. Upstream recommends bunx/npx for install.
RUN npm install -g \
      mcporter@0.7.3 \
      opencode-ai@1.2.6 \
      @openai/codex@0.104.0

# --- mise (runtime version manager) ---
# Install binary to /usr/local/bin, data to /opt/mise (shared across users)
# SECURITY: mise install script is dynamic and changes per release; SHA256 pinning
# is impractical. Using download-then-execute pattern with --fail (via -f flag)
# to avoid executing error pages. Review script on version bumps.
ENV MISE_DATA_DIR=/opt/mise
RUN curl -fsSL https://mise.run -o /tmp/mise-install.sh && \
    MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/mise-install.sh && \
    rm /tmp/mise-install.sh && \
    mkdir -p /opt/mise && \
    mise install node@18 node@20 node@22 node@24 && \
    chmod -R a+rX /opt/mise

# Ensure /home/node dirs exist for the non-root user
RUN mkdir -p /home/node/.local/bin /home/node/.local/share && \
    chown -R node:node /home/node

ENV PATH="/home/node/.local/bin:/opt/mise/shims:/usr/local/bin:/usr/bin:/bin"
ENV LANG=C.UTF-8

# ---------------------------------------------------------------------------
# Stage 2: Gateway-only CLI layer
# ---------------------------------------------------------------------------
FROM base-common AS base-gateway

# Architecture strategy for multi-arch builds (set automatically by buildx):
# - TARGETARCH=amd64: Docker CLI uses x86_64 tarball, 1Password uses amd64 package.
# - TARGETARCH=arm64: Docker CLI uses aarch64 tarball, 1Password uses arm64 package.
# - CodexBar is currently installed only on amd64; arm64 builds skip it.
ARG TARGETARCH

# --- Docker CLI ---
ARG DOCKER_SHA256_AMD64=4f798b3ee1e0140eab5bf30b0edc4e84f4cdb53255a429dc3bbae9524845d640
ARG DOCKER_SHA256_ARM64=e6b53725a73763ab3f988c73f8772eaed429754c1a579db5ff11f21990fd1817
RUN case "${TARGETARCH}" in \
      amd64) DOCKER_ARCH=x86_64; docker_sha256="${DOCKER_SHA256_AMD64}" ;; \
      arm64) DOCKER_ARCH=aarch64; docker_sha256="${DOCKER_SHA256_ARM64}" ;; \
      *) echo "ERROR: Unsupported TARGETARCH for Docker CLI: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-27.5.1.tgz" -o /tmp/docker.tgz && \
    echo "${docker_sha256}  /tmp/docker.tgz" | sha256sum -c - && \
    tar -xzf /tmp/docker.tgz --strip-components=1 -C /usr/local/bin/ docker/docker && \
    rm /tmp/docker.tgz && \
    chmod +x /usr/local/bin/docker

# --- claude CLI (Anthropic) ---
# SECURITY: claude install script is dynamic; SHA256 pinning impractical.
# Using download-then-execute with --fail (via -f). Review on version bumps.
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    bash /tmp/claude-install.sh && \
    rm /tmp/claude-install.sh && \
    if [ -f /root/.local/bin/claude ]; then \
      cp /root/.local/bin/claude /usr/local/bin/claude; \
    else \
      echo "ERROR: Claude CLI installation failed: /root/.local/bin/claude not found" >&2; \
      exit 1; \
    fi

# --- 1Password CLI ---
# Check latest versions: https://developer.1password.com/docs/cli/
ARG OP_VERSION=2.30.0
ARG OP_SHA256_AMD64=cd5361b074cd40eb2b332885f35a4d61c74369919ced95190c885f4d4f739dc7
ARG OP_SHA256_ARM64=c0618a4d4defa5d61606dfb4eaf7d5f39cf6361382c4943449df95fa1f7cc310
RUN case "${TARGETARCH}" in \
      amd64) op_sha256="${OP_SHA256_AMD64}" ;; \
      arm64) op_sha256="${OP_SHA256_ARM64}" ;; \
    esac && \
    curl -sSfo /tmp/op.zip \
      "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_${TARGETARCH}_v${OP_VERSION}.zip" && \
    echo "${op_sha256}  /tmp/op.zip" | sha256sum -c - && \
    unzip -od /usr/local/bin /tmp/op.zip && \
    chmod +x /usr/local/bin/op && \
    rm /tmp/op.zip

# --- CodexBar CLI ---
# Check latest releases: https://github.com/steipete/CodexBar/releases
ARG CODEXBAR_VERSION=0.18.0-beta.2
ARG CODEXBAR_SHA256=a1a013d4b6988af259b7a9f996e92483ca10a1e5046cd7e34625790ef1d59029
RUN if [ "${TARGETARCH}" = "amd64" ]; then \
      curl -fsSL \
        "https://github.com/steipete/CodexBar/releases/download/v${CODEXBAR_VERSION}/CodexBarCLI-v${CODEXBAR_VERSION}-linux-x86_64.tar.gz" \
        -o /tmp/codexbar.tar.gz && \
      echo "${CODEXBAR_SHA256}  /tmp/codexbar.tar.gz" | sha256sum -c - && \
      tar -xzf /tmp/codexbar.tar.gz -C /usr/local/bin/ && \
      rm /tmp/codexbar.tar.gz; \
    else \
      echo "WARNING: Skipping CodexBar install on ${TARGETARCH} (no published ARM64 binary detected)."; \
    fi

# --- openclaw CLI alias (delegates to the Node app) ---
RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' \
      > /usr/local/bin/openclaw && \
    chmod +x /usr/local/bin/openclaw

# ---------------------------------------------------------------------------
# Stage 3: Gateway target
# ---------------------------------------------------------------------------
FROM base-gateway AS gateway

COPY --from=openclaw-build /app /app

# --- Playwright MCP: pre-install browser + MCP server for agent tool calls ---
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN npx -y playwright-core install --no-shell chromium && \
    npm install -g @playwright/mcp@0.0.68 && \
    ln -s /opt/playwright-browsers/chromium-*/chrome-linux/chrome /usr/bin/chromium

# Bake entrypoint into the image
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Bake config templates and scripts into the image (build context = repo root)
COPY config/openclaw.json.template /opt/config/openclaw.json.template
COPY config/mcporter.json /opt/config/mcporter.json
COPY scripts/bootstrap-opencode.sh /opt/scripts/bootstrap-opencode.sh
COPY scripts/hooks/ /opt/hooks/
COPY scripts/orchestration/ /opt/scripts/orchestration/
COPY integrations/opencode-discord-pipe/ /opt/integrations/opencode-discord-pipe/

# Bake brain-core skills into the image so boot-time sync can populate
# the brain workspace's shared-skills/ cache without needing brain-core
# as a sibling directory. The sync hook reads from /opt/brain-core/skills/.
COPY skills/ /opt/brain-core/skills/

# Bake plugins into the image (extensions loaded by OpenClaw at runtime)
COPY plugins/telegramuser/ /home/node/.openclaw/extensions/telegramuser/
COPY plugins/discorduser/ /home/node/.openclaw/extensions/discorduser/
COPY plugins/hindsight-retain/ /home/node/.openclaw/extensions/hindsight-retain/

# Install plugin npm dependencies (hindsight-retain has no package.json).
# Strip devDependencies first — telegramuser uses pnpm workspace:* refs that npm rejects.
RUN cd /home/node/.openclaw/extensions/telegramuser && \
    jq 'del(.devDependencies)' package.json > package.tmp.json && mv package.tmp.json package.json && \
    npm install --omit=dev && \
    cd /home/node/.openclaw/extensions/discorduser && npm install --omit=dev

# Create workspace mount points
RUN mkdir -p /opt/opencode /opt/config /opt/scripts /opt/hooks /opt/integrations && \
    chown node:node /opt/opencode

# Set execute permissions on orchestration scripts
RUN chmod +x /opt/scripts/orchestration/*.sh

# Install Discord pipe dependencies
RUN cd /opt/integrations/opencode-discord-pipe && npm install --production

ENV NODE_ENV=production
ENV HOME=/home/node
WORKDIR /app

# Run gateway as non-root (C-INFRA-1 fix)
RUN chown -R node:node /app /opt/config /opt/scripts /opt/hooks \
      /opt/integrations /opt/brain-core /opt/playwright-browsers \
      /home/node/.openclaw
USER node

ENTRYPOINT ["/entrypoint.sh"]

# ---------------------------------------------------------------------------
# Stage 4: Sandbox target
#
# Also serves as the browser container image for OpenClaw's native browser
# tool. When used as a browser container, the CMD runs Chromium with CDP +
# Xvfb + optional VNC. When used as an agent sandbox, OpenClaw overrides
# the CMD with its own entrypoint.
# ---------------------------------------------------------------------------
FROM base-common AS sandbox

RUN mkdir -p /workspace/config /home/node/.npm /home/node/sandbox && \
    chown -R node:node /workspace /home/node /home/node/sandbox

# --- Python packages for presentation skill ---
RUN pip install --break-system-packages --quiet \
      python-pptx==1.0.2 Pillow==12.1.1 "markitdown[pptx]==0.1.4"

# --- Playwright for banner generation and browser automation scripts ---
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN pip install --break-system-packages --quiet playwright==1.58.0 && \
    playwright install chromium

# --- Browser container support (Chromium + CDP + VNC) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      fonts-liberation \
      fonts-noto-color-emoji \
      novnc \
      socat \
      websockify \
      x11vnc \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/sandbox-browser-entrypoint.sh /usr/local/bin/openclaw-sandbox-browser
RUN chmod +x /usr/local/bin/openclaw-sandbox-browser

USER node
WORKDIR /workspace

CMD ["openclaw-sandbox-browser"]
