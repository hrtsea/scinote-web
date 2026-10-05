# Rails Agents — Installed Sources

This project's `.codebuddy/skills/` bundles **three** upstream Rails skill
collections, plus some third-party additions. They are recorded here so future
syncs do not require re-diffing from scratch.

## Source A — ThibautBaissac/rails_ai_agents

- **Upstream:** https://github.com/ThibautBaissac/rails_ai_agents
- **Base commit:** `03622f23b4c6c6934b7c4862a5b5895a9cfd4b2d` (2026-06-01)
- **Installed:** 2026-09-22
- **Converted:** Claude Code `.claude/` layout → CodeBuddy `.codebuddy/`
  - 19 agents → `skills/<name>/SKILL.md`, **rewritten** for this stack
  - 20 knowledge skills → `skills/<name>/SKILL.md` (19 byte-identical to upstream)
  - 15 path-scoped rules → consolidated into `rules/rails-conventions.md`
  - `agents/references/*` → `skills/references/<topic>/` (byte-identical upward)
- **Not installed (no CodeBuddy equivalent):** `commands/` (26 slash commands),
  `.specify/` SDD scaffolding, `settings.json` hooks, `.claude_37signals/`,
  `mcp/sentry_monitor/`, `docs/`.

### Agent skills (19)

| Skill | Domain | Upstream model |
|---|---|---|
| model-agent | app/models/** | sonnet |
| controller-agent | app/controllers/** | sonnet |
| service-agent | app/services/** | sonnet |
| rspec-agent | spec/** | sonnet |
| migration-agent | db/migrate/** | sonnet |
| policy-agent | app/policies/** (Canaid here) | sonnet |
| job-agent | app/jobs/** (Delayed Job) | sonnet |
| implementation-agent | cross-layer features | sonnet |
| tdd-refactoring-agent | refactors | sonnet |
| form-agent | app/forms/** | sonnet |
| mailer-agent | app/mailers/** | sonnet |
| query-agent | app/queries/** | sonnet |
| presenter-agent | app/presenters/** | sonnet |
| viewcomponent-agent | app/components/** | sonnet |
| tailwind-agent | styling | sonnet |
| turbo-agent | Turbolinks (not Hotwire) | sonnet |
| stimulus-agent | app/javascript/controllers/** | sonnet |
| database-reviewer | schema/queries | sonnet |
| lint-agent | RuboCop/Brakeman/audit | sonnet |

### Knowledge skills (20)

`accessibility-review`, `action-cable-patterns`, `active-storage-setup`,
`api-versioning`, `authentication-flow`, `behavioral-guidelines`,
`caching-strategies`, `code-review`, `codex-review`, `dependabot-review`,
`extraction-timing`, `friction-review`, `i18n-patterns`, `mutation-testing`,
`performance-optimization`, `postgres-patterns`, `rails-architecture`,
`rails-concern`, `security-audit`, `solid-queue-setup`.

**Local divergence — `rails-architecture`:** the only knowledge skill that is
*not* byte-identical. Local version is deliberately pinned to Rails ~7.2 with
this project's stack (Devise + Canaid + Doorkeeper, Delayed Job, Sprockets,
Turbolinks) and drops the upstream multi-tenancy-by-default assumption.
**Do not overwrite it with upstream.**

### Known content gaps in the consolidated rules

`rules/rails-conventions.md` does not explicitly cover upstream's `cli-tools.md`
(`rg` over `grep`, `fd` over `find`) or `testing.md` (RSpec conventions).

## Source B — igmarin/rails-agent-skills

- **Upstream:** https://github.com/igmarin/rails-agent-skills
- **Upstream version at install:** v8.0.0 (2026-09-26); HEAD
  `03195c52ee7760f1713df6c099181dd9764478ac` (2026-09-27)
- **Installed:** 2026-09-22 (pre-v8 layout), refreshed 2026-10-05 with the
  three v8 workflow entries
- **Installed:** 28 of 34 upstream dirs

### Name collision handling — preserve this

`code-review` exists in **both** sources. The igmarin copy is installed as
**`code-review-igmarin`**; the rails_ai_agents copy keeps the plain name.
`rails-review` points at `code-review-igmarin`. Do not rename either one.

### Workflow entries (v8 style, 3)

`rails-feature` (ordinary behavior change), `rails-review` (PR/diff review),
`rails-maintenance` (setup, cleanup, engine upkeep). These replace the old
persona routers. Each carries a `## Project Adaptations (scinote-web-develop)`
section.

### Atomic / specialist skills (25)

**Context & tests:** `load-context`, `setup-environment`, `plan-tests`,
`write-tests`, `test-service`, `test-engine`
**Quality & conventions:** `apply-code-conventions`, `apply-stack-conventions`,
`refactor-code`, `review-architecture`, `security-check`, `code-review-igmarin`
**Operations:** `implement-background-job`, `seed-database`,
`optimize-performance`, `review-migration`
**Web & APIs:** `implement-authorization`, `implement-graphql`,
`implement-hotwire`, `generate-api-collection`, `version-api`
**Engines:** `create-engine`, `create-engine-installer`, `extract-engine`,
`document-engine`, `review-engine`, `release-engine`, `upgrade-engine`

### Local divergence — 5 skills are *stricter* than upstream

Not byte-identical, and deliberately so. Keep the local versions:

| Skill | Local behaviour |
|---|---|
| `implement-authorization` | Detects the installed framework first; only adds Pundit/CanCanCan when the project permits |
| `release-engine` | Requires explicit user approval of gem name + version before `gem push` |
| `apply-code-conventions` | Mandates a two-argument structured `Rails.logger` call shape |
| `plan-tests` | Uses flat-layout relative links (`../write-tests/SKILL.md`) |
| `setup-environment` | Same content, missing only a trailing newline |

### Not installed

`api`, `code-quality`, `testing` — empty grouping dirs with no content.
Upstream also depends on `igmarin/ruby-core-skills` for 15 core skills
(DDD vocabulary, YARD docs, service objects, process/discipline skills); that
companion pack is **not** installed here.

## Source C — third-party additions

`dhh` (DHH-style review, from mattpocock skills), `rails-best-practices-core`,
`rails-security-multitenancy`, `rails-hotwire-realtime`, `rails-jobs`,
`rails-migrations`, `rails-testing`, `rails-webhooks`, `schematic`,
`engineering/`, `productivity/`, `misc/`, `in-progress/`, `deprecated/`.

## Project adaptations (all sources)

This project (`scinote-web-develop`) differs from the source defaults:

- Authz: **Canaid** (`app/permissions/`), not Pundit.
- Jobs: **Delayed Job**, not Solid Queue.
- JS: **Turbolinks** + Stimulus, not Hotwire/Turbo Frames.
- Assets: **Sprockets**, not Propshaft.
- Tests: upstream SciNote uses **RSpec**; our addons (`access_control`,
  `eln_ui`) use **minitest** via `./run_ac_tests.sh`.
- DB: PostgreSQL.

Skills note these in their "Project Adaptations" sections.

## Re-syncing from upstream

```bash
git clone --depth 1 https://github.com/<owner>/<repo>.git _staging_<repo>

# Compare one source against what is installed
for d in _staging_<repo>/skills/*/; do
  n=$(basename "$d")
  diff -rqwB "scinote-web/.codebuddy/skills/$n" "$d" >/dev/null 2>&1 \
    && echo "$n: SAME" || echo "$n: DIFF"
done
```

Notes:
- Always diff with `-wB` first. Most upstream churn against what is installed is
  whitespace-only and not worth porting.
- For source B, remember the `code-review` → `code-review-igmarin` rename.
- Never blindly `cp -r` over the tree: Sources A and B collide on `code-review`,
  and five source-B skills plus one source-A skill are intentionally diverged.
