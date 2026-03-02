---
name: code-review-orchestrator
description: "Orchestrate independent AI code reviews to find vulnerabilities and quality issues. Use when reviewing PRs, especially after fixes have been applied. Implements multi-phase review strategy to avoid tunnel vision and ensure both known fixes are verified and unknown issues are discovered."
---

# Code Review Orchestrator

Orchestrate multi-model AI code reviews with proper independence.

**Core principle:** Structured reviews fix known issues. Adversarial audits find unknown issues. You need both, and they must be independent.

---

## Workflow

### Phase 1: Initial Review (4 reviews in parallel)

**3 Focused Audits:**
1. **Security (Sonnet)** - Authorization, input validation, external integrations, data flow
2. **Architecture (Kimi)** - Patterns, separation of concerns, scalability, data modeling  
3. **Quality (GLM)** - Duplication, type safety, testing, readability

**1 Adversarial Audit (Sisyphus/OpenCode):**
- Full unbiased code review with zero constraints
- No specific focus area - fresh eyes on everything
- Discovers issues the focused audits miss

---

### Phase 2: Fix Implementation

1. Consolidate all Phase 1 findings (prioritized: P0 → P1 → P2 → P3)
2. Apply fixes via OpenCode or manual
3. Push and verify tests pass

---

### Phase 3: Final Review (4 reviews in parallel)

**3 Adversarial Audits (Sonnet, Kimi, GLM):**
- Full unbiased code review with ZERO context from Phase 1
- No knowledge of what was fixed
- Fresh perspective catches unknown vulnerabilities

**1 Fix Verification (Sisyphus/OpenCode):**
- Review against Phase 1 consolidated findings
- Confirm all issues addressed
- Check no regressions introduced

**Critical:** Phase 3 adversarial reviews must have ZERO knowledge of Phase 1 findings.

---

## Prompt Guidance

When orchestrating reviews, you'll have codebase context. Craft prompts based on:

**Focused reviews (Phase 1):**
- Direct model to specific concern area (security/architecture/quality)
- Request file:line references and severity
- Ask for specific examples from the codebase

**Adversarial reviews (Phase 1 & Phase 3):**
- No constraints, no focus area
- Emphasize fresh perspective: "You've never seen this code before"
- Request comprehensive review across all dimensions

**Fix verification (Phase 3):**
- Provide Phase 1 consolidated findings
- Ask to verify each issue resolved
- Check for regressions or new issues introduced by fixes

---

## Anti-Patterns

**❌ Checklist validation:** "Verify these 32 fixes" → validates list, misses new issues

**❌ Phase 3 context leakage:** Telling Phase 3 adversarial what was fixed → bias toward validation, not discovery

**❌ Same model all phases:** Use different models for diversity

**❌ Single focused lens:** Only security reviews miss architecture/quality issues

**❌ No independent audit:** Focused reviews converge on same blind spots

---

## Orchestration

```bash
# Phase 1: 3 focused + 1 adversarial
sessions_spawn agentId=${AGENT_ID} model=sonnet label=pr-security task="[security prompt]"
sessions_spawn agentId=${AGENT_ID} model=kimi label=pr-arch task="[architecture prompt]"
sessions_spawn agentId=${AGENT_ID} model=glm label=pr-quality task="[quality prompt]"
# OpenCode adversarial: full unbiased review

# Phase 2: Consolidate + fix

# Phase 3: 3 adversarial + 1 verification
sessions_spawn agentId=${AGENT_ID} model=sonnet label=pr-adv task="[fresh unbiased prompt, zero context]"
sessions_spawn agentId=${AGENT_ID} model=kimi label=pr-adv task="[fresh unbiased prompt, zero context]"
sessions_spawn agentId=${AGENT_ID} model=glm label=pr-adv task="[fresh unbiased prompt, zero context]"
# OpenCode verification: check Phase 1 findings resolved
```

---

## Success Metrics

**Phase 1:** 
- Focused audits find 15-30 issues across domains
- Adversarial audit finds 5-10 issues focused audits missed

**Phase 2:** All P0/P1 fixed

**Phase 3:**
- Adversarial audits find 0-5 new unknown vulnerabilities
- Verification confirms all Phase 1 issues resolved

---

**Reference:** Real failure case in `docs/LEARNINGS-2026-02-09-code-review-failure.md` (4 reviews missed P0 bug, fresh adversarial audit caught it)
