# Role Guide: Orchestrator

## What does an orchestrator agent do?
The Orchestrator is the "brain of brains." It lives at the gateway of your AI infrastructure, managing the lifecycles of all other agents. Its primary job is to ensure that the right agent is doing the right job at the right time. It handles spawning new agents, upgrading existing ones, and routing complex requests to the appropriate specialists.

## When to deploy one?
Deploy an Orchestrator as your first agent. It serves as the foundation for an AI-native organization. You need an Orchestrator when you have (or plan to have) multiple specialized agents and need a central point of coordination and management.

## What tools does it need?
An Orchestrator needs high-level management skills like `create-agent`, `manage-agent`, and `upgrade-agent`. It also requires access to the `hindsight` memory backend to maintain a global view of the organization's state and history. It typically runs in a non-sandboxed environment (`sandbox.mode: off`) to have the necessary permissions for agent management.
