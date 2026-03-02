#!/bin/sh
# bootstrap-opencode.sh — OpenCode/OHO persistent setup
#
# Architecture:
#   ~/.config/opencode → symlink → .opencode-home/ (persistent volume)
#   First boot: runs OHO installer with native providers
#   Later boots: recreates symlink (instant)
#
# Usage: add to compose command BEFORE `opencode serve`
set -e

RUNTIME="/home/node/.openclaw/.opencode-home"
CONFIG_LINK="/home/node/.config/opencode"
AUTH_STORE="/home/node/.openclaw/.opencode-auth"
AUTH_LINK="/home/node/.local/share/opencode"

# --- 1. Symlink ephemeral paths → persistent volume ---
mkdir -p "$RUNTIME" "$AUTH_STORE" "$(dirname "$CONFIG_LINK")" "$(dirname "$AUTH_LINK")"

# Config dir: ~/.config/opencode → .opencode-home/
if [ -L "$CONFIG_LINK" ]; then
  [ "$(readlink "$CONFIG_LINK")" = "$RUNTIME" ] || { rm "$CONFIG_LINK"; ln -s "$RUNTIME" "$CONFIG_LINK"; }
elif [ -e "$CONFIG_LINK" ]; then
  rm -rf "$CONFIG_LINK"
  ln -s "$RUNTIME" "$CONFIG_LINK"
else
  ln -s "$RUNTIME" "$CONFIG_LINK"
fi

# Auth dir: ~/.local/share/opencode → .opencode-auth/
if [ -L "$AUTH_LINK" ]; then
  [ "$(readlink "$AUTH_LINK")" = "$AUTH_STORE" ] || { rm "$AUTH_LINK"; ln -s "$AUTH_STORE" "$AUTH_LINK"; }
elif [ -e "$AUTH_LINK" ]; then
  rm -rf "$AUTH_LINK"
  ln -s "$AUTH_STORE" "$AUTH_LINK"
else
  ln -s "$AUTH_STORE" "$AUTH_LINK"
fi

# --- 2. Install OHO if not already installed ---
OHO_TIMEOUT="${OHO_INSTALL_TIMEOUT:-120}"
if [ ! -f "$RUNTIME/opencode.json" ] || ! grep -q "oh-my-opencode" "$RUNTIME/opencode.json" 2>/dev/null; then
  echo "[bootstrap-opencode] First boot — running OHO installer (timeout: ${OHO_TIMEOUT}s)..."
  if command -v timeout >/dev/null 2>&1; then
    timeout "$OHO_TIMEOUT" npx -y --install-strategy=shallow oh-my-opencode@${OHO_VERSION:-3.7.2} install \
      --no-tui \
      --claude=yes \
      --openai=yes \
      --gemini=yes \
      --copilot=no \
      --opencode-zen=yes \
      --zai-coding-plan=yes \
      --skip-auth || echo "[bootstrap-opencode] WARNING: OHO install failed or timed out — continuing without OHO"
  else
    npx -y --install-strategy=shallow oh-my-opencode@${OHO_VERSION:-3.7.2} install \
      --no-tui \
      --claude=yes \
      --openai=yes \
      --gemini=yes \
      --copilot=no \
      --opencode-zen=yes \
      --zai-coding-plan=yes \
      --skip-auth || echo "[bootstrap-opencode] WARNING: OHO install failed — continuing without OHO"
  fi
else
  echo "[bootstrap-opencode] OHO already installed."
fi

echo "[bootstrap-opencode] Ready: $CONFIG_LINK → $RUNTIME ✓"
