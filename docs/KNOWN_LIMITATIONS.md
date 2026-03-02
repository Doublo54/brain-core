# Known Limitations

## OpenClaw Permission Enforcement

### sandbox.mode
- `sandbox.mode` is a real runtime control in OpenClaw (not just advisory) based on upstream docs and schema: `off` runs tools on host, `all` runs tools in sandbox, `non-main` depends on session key classification.
- In this repo, we have configuration/docs evidence (`brain-core/config/reference.md`, `brain-core/docs/security-model.md`) and operational verification hooks (`openclaw sandbox explain`), but no local OpenClaw gateway source code vendored under `brain-core/` to independently trace enforcement internals.
- Practical implication: treat sandboxing as active control, but keep defense-in-depth assumptions (tool deny lists, elevated off) because sandboxing is not a perfect boundary.

### approval.mode
- `approval.mode` is enforced in channel plugin code for `telegramuser` and `discorduser` (manual mode queues drafts, auto mode sends immediately):
  - `brain-core/plugins/telegramuser/src/channel.ts`
  - `brain-core/plugins/discorduser/src/monitor.ts`
- There is no local evidence that `agents.list[].approval.mode` is enforced as a general per-agent runtime gate in this stack.
- The active deployment template no longer defines `agents.list[].approval.mode`; rely on channel-level approvals or exec approvals for enforceable human-in-the-loop controls.

### Inter-Agent Escalation Risk
With `allowAgents: ["*"]`, a sandboxed standard-tier agent (for example, `miro`) can call
an unsandboxed trusted-tier agent (for example, `carpincho`) to execute actions outside the
sandbox boundary. Approval mode helps where explicitly implemented, but it is not a universal
inter-agent guard.

**Accepted risk**: The benefit of open inter-agent communication currently outweighs this risk
for the present deployment scope.

## Workarounds
- Keep untrusted agents on `sandbox.mode: "all"` and keep `tools.elevated.enabled: false`.
- For trusted/unsandboxed agents, explicitly deny high-risk tools when not needed (`exec`, `process`, `gateway`, etc.).
- Restrict `subagents.allowAgents` from `"*"` to a minimal allowlist where possible.
- If human-in-the-loop is required, prefer channel-level approval queues (where code-level enforcement is visible) over assuming per-agent `approval.mode` enforcement.
