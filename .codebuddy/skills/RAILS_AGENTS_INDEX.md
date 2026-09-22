# Rails Agents (converted from rails_ai_agents)

Converted from `ThibautBaissac/rails_ai_agents` Claude Code config into CodeBuddy
skills. Each agent became a skill under `skills/<name>/SKILL.md`.

## Skills (19)

| Skill | Domain | Original model |
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

## Rules

Consolidated path-scoped rules → `rules/rails-conventions.md` (always loaded).

## Deep references

Original `agents/references/*` copied to `skills/references/<topic>/`. Each topic dir
holds pattern/anti-pattern libraries. When a skill needs deeper guidance, read the
matching file, e.g. `skills/references/model/` for model-agent.

## Project adaptations

This project (`scinote-web-develop`) differs from the source defaults:
- Authz: **Canaid** (`app/permissions/`), not Pundit.
- Jobs: **Delayed Job**, not Solid Queue.
- JS: **Turbolinks** + Stimulus, not Hotwire/Turbo Frames.
- Assets: **Sprockets**, not Propshaft.
- DB: PostgreSQL.

Skills already note these in their "Project Adaptations" sections.
