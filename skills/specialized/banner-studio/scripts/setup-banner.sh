#!/bin/bash
# Setup script for banner-studio skill
# Installs Playwright + Chromium and runs a smoke test

set -e

echo "=== Installing Banner Studio dependencies ==="

# 1. Verify python3
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found. Install Python 3.8+ first."
  exit 1
fi
echo "python3 found: $(python3 --version)"

# 2. Install Playwright Python package
pip install playwright --break-system-packages --quiet 2>/dev/null || \
pip install playwright --quiet 2>/dev/null || \
pip3 install playwright --break-system-packages --quiet
echo "playwright package installed"

# 3. Install Chromium browser
playwright install chromium
echo "Chromium browser installed"

# 4. Verify Playwright imports
python3 -c "
from playwright.sync_api import sync_playwright
print('Playwright imports OK')
"

# 5. Smoke test: render minimal-banner.html
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${BASE_DIR}/assets/templates/minimal-banner.html"
OUTPUT="/tmp/banner-studio-smoke-test.png"

if [ -f "$TEMPLATE" ]; then
  python3 "${SCRIPT_DIR}/generate.py" \
    --template minimal-banner.html \
    --data '{"title": "Smoke Test", "subtitle": "Banner Studio Ready", "accent_color": "#6C5CE7"}' \
    --output "$OUTPUT"

  if [ -f "$OUTPUT" ]; then
    SIZE=$(wc -c < "$OUTPUT")
    echo "Smoke test passed: ${OUTPUT} (${SIZE} bytes)"
    rm -f "$OUTPUT"
  else
    echo "ERROR: Smoke test failed — output file not created"
    exit 1
  fi
else
  echo "WARNING: minimal-banner.html not found, skipping smoke test"
fi

echo "=== Banner Studio setup complete ==="
