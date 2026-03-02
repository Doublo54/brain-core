# Overlay Repository Guide

This guide explains how to create and manage a business-specific **Overlay Repository** on top of `brain-core`. 

The overlay pattern allows you to keep your infrastructure (deployment, orchestration scripts, core skills) separate from your business logic (agent identities, specialized skills, and proprietary knowledge).

---

## The Overlay Concept

`brain-core` is a generic template providing the "body" of the system:
- Docker infrastructure and deployment runbooks
- Orchestration scripts for multi-agent task management
- Core operational skills (create-agent, upgrade-agent)
- Reusable behavioral skills (memory-brain, proactive-behavior)

An **Overlay Repository** (e.g., `{org}-brain`) provides the "mind":
- Unique agent identities (`IDENTITY.md`, `SOUL.md`)
- Business-specific knowledge bases (`knowledge/`)
- Specialized domain skills (e.g., `trading-orchestrator`, `customer-support`)
- Organization-specific documentation

At runtime, the overlay repository is mounted over the `brain-core` workspace, creating a unified environment for the agents.

---

## Directory Structure

A standard overlay repository should follow this structure:

```text
overlay-repo/
├── agents/                          # Individual agent brains
│   ├── agent-alpha/                 # Brain for Agent Alpha
│   │   ├── IDENTITY.md              # Who this agent is
│   │   ├── SOUL.md                  # How this agent thinks
│   │   ├── USER.md                  # Information about the owner
│   │   ├── brain.yaml               # Agent-specific configuration
│   │   ├── knowledge/               # Agent-specific knowledge
│   │   ├── skills/                  # Agent-specific skills
│   │   └── docs/                    # Agent-specific documentation
│   └── agent-beta/                  # Brain for Agent Beta
│       └── ...
├── shared-skills/                   # Skills shared across multiple agents
│   ├── business-logic-skill/
│   └── common-utility-skill/
├── shared-docs/                     # Documentation shared across agents
│   ├── SECURITY.md
│   └── GUIDELINES.md
└── knowledge/                       # Global business knowledge base
```

---

## Docker Volume Mount Pattern

The overlay repository is integrated with `brain-core` using Docker volume mounts. In a production environment (like Coolify), the overlay repo is typically cloned onto the host and mounted into the gateway container.

### Mount Point
The standard mount point for the overlay content is:
`/home/node/.openclaw/workspace`

### Example Compose Configuration
```yaml
services:
  openclaw:
    volumes:
      - /path/to/overlay-repo:/home/node/.openclaw/workspace
```

This mount ensures that when the OpenClaw gateway starts, it sees the agents and resources defined in your overlay repository.

---

## Agent-Specific Customization

Each agent in the `agents/` directory is a self-contained "brain". The following files define the agent's persona and behavior:

### 1. IDENTITY.md
Defines the agent's name, role, and core purpose. This is the primary source of truth for the agent's self-conception.

### 2. SOUL.md
Defines the agent's personality, communication style, and decision-making framework. It guides how the agent interacts with users and other agents.

### 3. USER.md
Contains information about the user or organization the agent serves. This helps the agent provide personalized assistance and understand the broader context of its work.

### 4. brain.yaml
The technical configuration for the agent, including:
- Model selection (e.g., `anthropic/claude-3-5-sonnet`)
- Tool permissions (allow/deny lists)
- Memory settings
- Environment variable requirements

### 5. knowledge/
A directory containing Markdown files, PDFs, or other documents that provide the agent with domain-specific information.

---

## Shared vs. Agent-Specific Skills

To maintain a DRY (Don't Repeat Yourself) architecture, the overlay pattern distinguishes between shared and agent-specific skills.

### Shared Skills
Shared skills are stored in the `shared-skills/` directory at the root of the overlay repository. They are made available to individual agents via **symbolic links**.

**Example:**
If `agent-alpha` needs the `memory-brain` skill:
`agents/agent-alpha/skills/memory-brain` -> `../../../shared-skills/memory-brain`

This allows you to update a skill in one place and have the changes propagate to all agents using it.

### Agent-Specific Skills
Skills that are unique to a single agent should be stored as regular files/directories directly within that agent's `skills/` directory.

**Example:**
A `coding-orchestrator` skill that only the "Lead Developer" agent uses should live in `agents/lead-developer/skills/coding-orchestrator/`.

---

## Shared Documentation

Similar to skills, documentation that applies to all agents (like security policies or coding standards) should be stored in `shared-docs/` and symlinked into each agent's `docs/` directory.

This ensures consistency across the entire agent fleet while allowing individual agents to have their own divergent documentation where necessary.

---

## Reference Implementation: {org}-brain

The `{org}-brain` repository serves as the primary reference implementation for this overlay pattern. It demonstrates:

1.  **Multi-Agent Setup**: Four distinct agents with unique identities and roles.
2.  **Symlinked Shared Skills**: Reusing `memory-brain` and `proactive-agent-behavior` across all agents.
3.  **Specialized Skills**: Agent-specific implementations of `create-agent` and `coding-orchestrator`.
4.  **Shared Infrastructure Docs**: Symlinking `SECURITY.md` and `HEARTBEAT.md` from a central location.
5.  **Divergent Documentation**: Allowing specific agents to maintain their own unique documentation sets while sharing the core.

---

## Best Practices for Overlay Repositories

1.  **Keep it Generic**: Avoid hardcoding infrastructure details (like IP addresses or specific host paths) in the overlay. Use environment variables instead.
2.  **Use Symlinks for Consistency**: Always symlink shared resources rather than copying them.
3.  **Version Control**: Keep your overlay repository in its own Git repo. This allows you to version your business logic independently of the `brain-core` infrastructure.
4.  **Atomic Commits**: When updating shared skills, ensure the changes are compatible with all agents using that skill.
5.  **Documentation**: Keep the `knowledge/` and `shared-docs/` directories well-organized and up-to-date. The quality of an agent's output is directly tied to the quality of its knowledge base.
