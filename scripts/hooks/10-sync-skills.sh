#!/bin/sh
# 10-sync-skills.sh — Populate shared-skills/ cache at boot
#
# Syncs brain-core skills (baked into the image at /opt/brain-core/skills/)
# into the brain workspace's shared-skills/ directory. This ensures agent
# skill symlinks resolve without requiring shared-skills/ to be committed
# to the brain repository.
set -e

BRAIN_WORKSPACE="/opt/brain"
BRAIN_CORE="/opt/brain-core"
SYNC_SCRIPT="$BRAIN_WORKSPACE/scripts/sync-skills.sh"

if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "[hook:sync-skills] No sync script at $SYNC_SCRIPT, skipping"
  exit 0
fi

if [ ! -d "$BRAIN_CORE/skills" ]; then
  echo "[hook:sync-skills] No brain-core skills at $BRAIN_CORE/skills, skipping"
  exit 0
fi

echo "[hook:sync-skills] Syncing brain-core skills to $BRAIN_WORKSPACE/shared-skills/..."
bash "$SYNC_SCRIPT" "$BRAIN_CORE"
echo "[hook:sync-skills] Done"
