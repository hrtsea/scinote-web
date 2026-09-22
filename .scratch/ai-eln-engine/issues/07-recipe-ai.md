# 07 — 配方智能处理（AI-201~203）

**What to build:** 多组分配方 AI 处理（配方=Form 模板 + Table 实例，关联 Repository 行）：AI-201 非结构化文本解析配方（自由文本→组分/质量体积/摩尔占比→Form 结构 JSON 预览，确认后导入新建配方条目）、AI-202 配比校验辅助（读 Form/Table，提示总和异常/单位冲突，仅提示不改数据）、AI-203 历史实验参数建议（读项目已完成实验，给候选配方参数，预览后新建实验/配方模板）。

**Blocked by:** 04 — AI 侧边抽屉 UI 与权限条件渲染; 02 — AI 数据模型迁移

**Status:** ready-for-agent

- [ ] AI-201 文本解析：自由文本→Form 结构预览，确认后导入新建配方（FormResponse/Table）
- [ ] AI-202 配比校验：读现有配方，提示异常/冲突，不自动修改
- [ ] AI-203 参数建议：读项目历史，给候选参数表单预览，确认后新建
- [ ] 配方关联使用多态 `ai_sessionable`（FormResponse/Table），原生表零改动
- [ ] 符合 ADR-0001（recipe→Form/Table 映射）、ADR-0004（管道）
