
## 2026-02-13T21:44:58Z — Task 3 Decisions
- Adopted canonical workspace discovery order for orchestration scripts: `(1) WORKSPACE env var`, `(2) positional arg $1`, `(3) current working directory`.
- Kept `SCRIPT_DIR` only for sibling script dispatch (image-baked executable lookup), and explicitly banned it for mutable state/config path derivation.
- Standardized per-agent state isolation root to `$WORKSPACE/state` for all runtime JSON, lock, PID, and health files.
- Standardized per-agent config root to `$WORKSPACE/config` with subpaths `$WORKSPACE/config/repo-configs` and `$WORKSPACE/config/templates`.
- Standardized GitHub credential precedence to `GITHUB_TOKEN_${AGENT_ID}` override with `GITHUB_TOKEN` fallback using Bash indirect expansion.
- Marked shared `.sisyphus` symlink under `WORKSPACES_ROOT` as multi-agent collision risk to address in implementation phase.
