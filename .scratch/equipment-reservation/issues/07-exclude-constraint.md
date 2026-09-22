# 07 — 数据库 EXCLUDE 约束（可选/降级，D2.5）

Type: task
Status: ready-for-agent
Blocked by: 01, 02

> 默认 deferred。与「权限覆盖」（02/03）互斥，启用即放弃覆盖能力，二选一。

**What to build:** Postgres `EXCLUDE USING gist (subject_id WITH =, tstzrange(start_datetime, end_datetime, '[)') WITH &&) WHERE (event_type = 0 AND status IN (0,1))`，根治 TOCTOU。

**Checklist**
- [ ] **前提**：`start_datetime/end_datetime` 规整时区或改 `timestamptz`；全天 `date` 并入同一 range
- [ ] raw SQL 迁移（`structure.sql` 管理）
- [ ] **决策门槛**：仅当某部署禁用覆盖且要求原子性时启用

**Done when:** 如启用，原子性约束生效且覆盖能力关闭。
