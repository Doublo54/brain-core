#!/usr/bin/env bash
# =============================================================================
# Sandbox Browser Container Entrypoint
#
# Starts Chromium with CDP (Chrome DevTools Protocol) enabled, an Xvfb virtual
# display, and optional VNC/noVNC for visual observation.
#
# OpenClaw's native browser tool communicates with this container via CDP.
# The gateway creates one browser container per sandboxed agent (agent-scoped)
# or one shared container (shared scope).
#
# Environment variables (all optional, with sane defaults):
#   OPENCLAW_BROWSER_CDP_PORT    — CDP listen port (default: 9222)
#   OPENCLAW_BROWSER_VNC_PORT    — VNC listen port (default: 5900)
#   OPENCLAW_BROWSER_NOVNC_PORT  — noVNC listen port (default: 6080)
#   OPENCLAW_BROWSER_ENABLE_NOVNC — Enable noVNC web viewer (default: 1)
#   OPENCLAW_BROWSER_HEADLESS    — Run headless (default: 0)
# =============================================================================
set -euo pipefail

export DISPLAY=:1
export HOME=/tmp/openclaw-home
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_CACHE_HOME="${HOME}/.cache"

CDP_PORT="${OPENCLAW_BROWSER_CDP_PORT:-9222}"
VNC_PORT="${OPENCLAW_BROWSER_VNC_PORT:-5900}"
NOVNC_PORT="${OPENCLAW_BROWSER_NOVNC_PORT:-6080}"
ENABLE_NOVNC="${OPENCLAW_BROWSER_ENABLE_NOVNC:-1}"
HEADLESS="${OPENCLAW_BROWSER_HEADLESS:-0}"

mkdir -p "${HOME}" "${HOME}/.chrome" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}"

# --- Virtual framebuffer (always needed, even headless uses it as fallback) ---
Xvfb :1 -screen 0 1280x800x24 -ac -nolisten tcp &

# --- Chromium launch args ---
if [[ "${HEADLESS}" == "1" ]]; then
  CHROME_ARGS=("--headless=new" "--disable-gpu")
else
  CHROME_ARGS=()
fi

# Validate CDP_PORT is numeric and in valid range
if ! [[ "${CDP_PORT}" =~ ^[0-9]+$ ]] || [[ "${CDP_PORT}" -lt 1 || "${CDP_PORT}" -gt 65535 ]]; then
  echo "FATAL: Invalid CDP_PORT='${CDP_PORT}' (must be 1-65535). Exiting." >&2
  exit 1
fi

# CDP listens on loopback internally; socat exposes it on 127.0.0.1 below
if [[ "${CDP_PORT}" -ge 65535 ]]; then
  CHROME_CDP_PORT="$((CDP_PORT - 1))"
else
  CHROME_CDP_PORT="$((CDP_PORT + 1))"
fi

CHROME_ARGS+=(
  "--remote-debugging-address=127.0.0.1"
  "--remote-debugging-port=${CHROME_CDP_PORT}"
  "--user-data-dir=${HOME}/.chrome"
  "--no-first-run"
  "--no-default-browser-check"
  "--disable-dev-shm-usage"
  "--disable-background-networking"
  "--disable-features=TranslateUI"
  "--disable-breakpad"
  "--disable-crash-reporter"
  "--metrics-recording-only"
  "--no-sandbox"
)

MAX_RETRIES=3
CDP_READY=0

for attempt in $(seq 1 "${MAX_RETRIES}"); do
  chromium "${CHROME_ARGS[@]}" about:blank &
  CHROMIUM_PID=$!

  for _ in $(seq 1 100); do
    if ! kill -0 "${CHROMIUM_PID}" 2>/dev/null; then
      break
    fi
    if curl -sS --max-time 1 "http://127.0.0.1:${CHROME_CDP_PORT}/json/version" >/dev/null 2>&1; then
      CDP_READY=1
      break
    fi
    sleep 0.2
  done

  if [[ "${CDP_READY}" == "1" ]]; then
    break
  fi

  echo "Chromium failed to start (attempt ${attempt}/${MAX_RETRIES}), cleaning up..." >&2
  kill "${CHROMIUM_PID}" 2>/dev/null || true
  wait "${CHROMIUM_PID}" 2>/dev/null || true
  rm -f "${HOME}/.chrome/SingletonLock" "${HOME}/.chrome/SingletonSocket" 2>/dev/null || true
  sleep 1
done

if [[ "${CDP_READY}" != "1" ]]; then
  echo "FATAL: Chromium CDP not reachable after ${MAX_RETRIES} attempts. Exiting." >&2
  exit 1
fi

socat \
  TCP-LISTEN:"${CDP_PORT}",fork,reuseaddr,bind=127.0.0.1 \
  TCP:127.0.0.1:"${CHROME_CDP_PORT}" &

if [[ "${ENABLE_NOVNC}" == "1" && "${HEADLESS}" != "1" ]]; then
  VNC_PASSWORD="${VNC_PASSWORD:-$(head -c 8 /dev/urandom | hexdump -v -e '/1 "%02x"')}"
  x11vnc -display :1 -rfbport "${VNC_PORT}" -shared -forever -passwd "${VNC_PASSWORD}" -localhost &
  websockify --web /usr/share/novnc/ "127.0.0.1:${NOVNC_PORT}" "localhost:${VNC_PORT}" &
fi

wait -n
