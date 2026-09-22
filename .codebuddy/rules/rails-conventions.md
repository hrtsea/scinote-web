# Rails Conventions (adapted from rails_ai_agents)

Converted from Claude Code `.claude/rules/*.md` (path-scoped rules). CodeBuddy has
no path-scoped rule mechanism, so these are consolidated into one always-loaded file.
Path hints preserved as comments for reference.

## Principles (always)

- Skinny Everything: Controllers orchestrate. Models persist. Services contain business
  logic. Views display.
- Callbacks only for data normalization (`before_validation`, `before_save`). Side effects
  (emails, jobs, APIs) belong in services.
- Services: `.call` class method, return Result objects, namespace by domain
  (`Entities::CreateService`).
- No premature abstraction: three similar lines > wrong abstraction.
- Explicit > implicit: clear service calls over hidden callbacks.

## Anti-Patterns to Avoid (app/**, spec/**)

- God Model: model > ~200 lines → extract to services/query objects.
- Service Graveyard: don't create services for trivial CRUD (`user.update!` inline is fine).
- Callback Spaghetti: never chain `after_create`/`after_save` for emails, jobs, APIs.
- STI Abuse: >20% subtype-specific columns → use polymorphic associations.
- N+1 Ignorance: eager-load with `includes`/`preload`; use `strict_loading` in dev.
- Kitchen Sink Concern: concerns narrow & focused (`SoftDeletable`, `Sluggable`);
  >~30 lines or multi-responsibility = hidden service object.

## Models (app/models/**)

- Persistence only: validations, associations, scopes, simple predicates.
- Extract business logic to services; complex queries to query objects.

## Controllers (app/controllers/**)

- Thin, RESTful. Delegate to services. Strong params.

## Services (app/services/**)

- `.call`, Result objects, namespace by domain.

## Views & Components (app/views/**, app/components/**)

- ViewComponents (`app/components/`) for reusable UI over partials.
- Presenters (`app/presenters/`, SimpleDelegator) for formatting logic.
- No business logic in views.
- Tailwind utility classes for styling.
- ARIA attributes for accessibility (WCAG 2.1 AA).

## Jobs (app/jobs/**) — NOTE: this project uses Delayed Job, not Solid Queue

- Jobs must be idempotent (safe to retry).
- Pass IDs, not full objects.
- `discard_on ActiveRecord::RecordNotFound`.
- `retry_on` with specific exceptions and limits.
- One job, one responsibility.
- Test with `have_enqueued_job`.

## Mailers (app/mailers/**, app/views/**/*_mailer/**)

- Always HTML + text templates.
- `deliver_later` (async via Delayed Job), never `deliver_now` in controllers.
- Previews in `spec/mailers/previews/`.
- Minimal logic; formatting in presenters.

## Migrations (db/migrate/**, db/schema.rb)

- Always reversible: prefer `change` over `up`/`down`.
- `null: false` for required columns; DB-level defaults where appropriate.
- Index foreign keys and frequently queried columns.
- Unique indexes for uniqueness validations.
- `references ... foreign_key: true` for associations.
- Never modify a run migration — create a new one.
- Zero-downtime: add column → backfill → add constraint.

## Policies (app/policies/**) — NOTE: this project uses Canaid, not Pundit

- One permission file per domain: `permissions/<domain>_permissions.rb`.
- Default deny; define permission blocks for each action.
- Test every action for every role.

## Queries (app/queries/**)

- Single responsibility; constructor accepts context (`account:`/`user:`).
- Return `ActiveRecord::Relation` or `Hash`; public `#call`.
- `includes`/`preload`/`eager_load` to prevent N+1.
- Read-only; sanitize input (`sanitize_sql_like`, parameterized queries).
- Simple one-liners stay as model scopes.

## CLI Commands (reference)

```bash
bundle exec rspec                                # Full suite
bundle exec rspec spec/models/user_spec.rb       # Single file
bundle exec rspec spec/models/user_spec.rb:25    # Single example (line)
bundle exec rubocop -a                           # Auto-fix safe cops
bin/brakeman --no-pager                          # Static analysis
bundle exec bundler-audit check --update         # Gem vulnerabilities
bin/rails db:migrate                             # Run migrations
bin/rails db:migrate:status                      # Check status
bin/rails console                                # Interactive console
```

## CLI Tools

- `rg` instead of `grep -r` (gitignore-aware).
- `fd` instead of `find` (gitignore-aware).
- Security review: run `semgrep --config=auto .` first; treat findings as facts.

## Caveman Mode (optional, user-triggered `caveman`)

Respond terse. Drop articles/filler/pleasantries/hedging. Keep code blocks, error
strings, API/class/file names exact. Pattern: `[thing] [action] [reason]. [next step].`
Drop terse mode for security warnings, destructive ops, multi-step ambiguity.
