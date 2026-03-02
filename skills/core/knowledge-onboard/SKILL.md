---
name: knowledge-onboard
version: 1.0.0
description: "Interactive interview flow for setting up organization-specific knowledge files when deploying brain-core to a new organization. Guides the user through defining the core identity, team, products, and culture of the org."
---

# Knowledge Onboarding

This skill provides an interactive interview flow to bootstrap the foundational knowledge files for a new organization. It is designed to capture the "soul" and operational context of the org through a structured conversation.

## Purpose

This skill is for **new organization setup** and **initial deployment**. It focuses on capturing high-level organizational context that isn't easily found in technical documentation.

**Note:** This is NOT for bulk document ingestion or RAG setup. That is handled by separate data ingestion pipelines. This is about defining the core identity and conventions of the organization.

---

## Interview Phases

The onboarding process is divided into five phases. Conduct these conversationally, asking one or two questions at a time to avoid overwhelming the user.

### 1. Organization Basics
Gather the fundamental identity of the organization.
- **Name:** What is the official name of the organization?
- **Industry:** What sector does it operate in?
- **Mission/Vision:** What is the core purpose or "North Star"?
- **Products/Services:** What does the organization actually do or build at a high level?

### 2. Team Structure
Understand the human element and how they interact.
- **Key Members:** Who are the primary stakeholders and team members?
- **Roles:** What are their titles and responsibilities?
- **Communication Preferences:** How do they like to be addressed? Any specific "vibe" (formal vs. casual)?
- **Availability:** Timezones and typical working hours.

### 3. Products & Projects
Deep dive into the active work.
- **Active Projects:** What are the top 3-5 priorities right now?
- **Repositories:** Where is the code? (GitHub orgs, specific repos).
- **Tech Stack:** What are the primary languages, frameworks, and infrastructure used?

### 4. Culture & Conventions
Capture the unwritten rules and operational style.
- **Communication Style:** Async-first? Meeting-heavy? Slack/Discord vs. Email?
- **Decision Making:** Who has final say? Is it consensus-driven or hierarchical?
- **Approval Flows:** How do tasks move from "In Progress" to "Done"?
- **Conventions:** Any specific naming conventions, coding standards, or documentation requirements?

### 5. Tools & Integrations
Identify the ecosystem the brain will live in.
- **Primary Tools:** What does the team use daily? (e.g., Discord, Slack, ClickUp, Jira, GitHub, Notion).
- **Integrations:** Which of these should the brain eventually interact with?

---

## Output Structure

The answers from the interview should be synthesized and written to the following files in the `knowledge/` directory:

| File Path | Content Description |
|-----------|---------------------|
| `knowledge/{org-name}/overview.md` | Organization basics, mission, and high-level identity. |
| `knowledge/team/members.md` | Team roster, roles, and communication preferences. |
| `knowledge/{org-name}/products.md` | Active products, projects, and tech stack details. |
| `knowledge/{org-name}/culture.md` | Culture, communication style, and operational conventions. |
| `knowledge/{org-name}/tools.md` | List of tools, integrations, and access patterns. |

---

## Guidance on Usage

### When to use:
- **First-time deployment:** When setting up a brain for a brand new organization.
- **New Org Onboarding:** When an existing brain-core instance is being adapted for a new client or department.
- **Major Restructure:** When an organization undergoes a significant change in mission, team, or tooling.

### How to execute:
1. Start by explaining the goal: "I'm going to help you set up the foundational knowledge for [Org Name]."
2. Move through the phases sequentially.
3. After each phase, summarize what you've learned and ask for corrections.
4. Once all phases are complete, propose the file structure and content before writing to disk.

---

## Safety & Constraints

- **No Bulk Ingestion:** Do not attempt to read hundreds of PDFs or crawl entire websites during this flow.
- **Privacy:** Remind the user not to provide sensitive personal information or secrets (API keys, passwords) during the interview.
- **Draft First:** Always show the drafted markdown content to the user for approval before creating the files.
