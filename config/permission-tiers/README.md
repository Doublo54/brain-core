# Permission Tier Reference Configs

These JSON files document the 4-tier agent permission model for brain-core.

**These are reference documentation, NOT runtime configuration.**
OpenClaw enforces permissions through its own agent config in `openclaw.json.template`.
These files exist to:
- Document what each tier allows/restricts
- Guide agent creation (which tier to assign)
- Serve as reference for the create-agent and upgrade-agent skills

## Tiers

| Tier | Sandbox | Use Case |
|------|---------|----------|
| admin | off | Orchestrator agents managing other agents |
| trusted | off | Coding agents needing exec/docker/git |
| standard | all (agent-scoped) | Business agents (sales, finance, etc.) |
| restricted | all (session-scoped, ro) | Untrusted/community agents |

## Usage
When creating a new agent, reference the appropriate tier config to set sandbox mode, tool policies, and MCP server access in `openclaw.json.template`.
