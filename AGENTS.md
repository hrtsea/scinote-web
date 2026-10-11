# AGENTS.md

## Agent skills

### Issue tracker

Issues and specs live as markdown files in `.scratch/` (one dir per feature, tickets under `issues/`). Not GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles, each using the label string equal to its role name (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: ADRs live in `docs/adr/` (NNNN-slug.md) as the single source of truth; `CONTEXT.md` glossary files are per-feature under `docs/开发计划/*/` (e.g. `docs/开发计划/ai-eln/CONTEXT.md`), not at repo root. `docs/ARCHITECTURE_DECISIONS.md` is only an index. See `docs/agents/domain.md`.

### Vue 页查找

给定 Rails 路由找对应 Vue SFC：在 ERB 视图里 grep `javascript_include_tag` 拿 entry 名 → 在 `config/webpack/webpack.config.js` 查该 entry → SFC 在 `app/javascript/{packs/vue, vue}/<entry>`。teams 设置区 entry：`vue_teams_table`(列表)、`vue_team_members`(成员)、`vue_team_new`(新建)、`vue_team_preferences`(show 通用设置)。迁移状态见 `docs/vue-migration-audit.md`。
