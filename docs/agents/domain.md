# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — single-context repo, so there is no `CONTEXT-MAP.md`.
- **`docs/ARCHITECTURE_DECISIONS.md`** — the ADR log for this repo. Read the ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/
│   └── ARCHITECTURE_DECISIONS.md   ← ADR log (ADR-001 … ADR-005)
└── app/
```

## ADR convention

This repo keeps ADRs in one consolidated file, `docs/ARCHITECTURE_DECISIONS.md`, under the
section **三、关键架构决策（ADR）**, numbered `ADR-00N`. Append new ADRs there; do not
create a parallel `docs/adr/` directory.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-001 (Repository 自定义表模式是核心领域模型) — but worth reopening because…_
