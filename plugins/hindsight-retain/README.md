# openclaw-hindsight-retain

Standalone source of truth for the `hindsight-retain` OpenClaw extension.

## Contents
- `index.ts` — extension implementation
- `openclaw.plugin.json` — plugin manifest
- `.gitignore` — excludes runtime `data/`

## Origin
Extracted from agent brain workspace extension path:
`.openclaw/extensions/hindsight-retain/`

## Notes
- Runtime state is intentionally not versioned.
- Configure credentials/endpoints via OpenClaw config/env, not in this repo.
