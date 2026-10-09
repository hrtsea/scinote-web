<template>
  <!-- 实验记录本（画布 4:72 / 4:899）：页头 + 筛选栏 + 记录布局（左记录流 + 右目录统计 320） -->
  <div class="notebook">
    <!-- 页头 4:900 -->
    <PageHeader
      title="实验记录本"
      subtitle="跨实验聚合视图 · 记录本实体挂在任务层，本页按任务/实验/项目三个维度回溯（DEC-010）"
    >
      <template #right>
        <div class="head-actions">
          <button class="eln-btn-ghost lg">导出选中记录</button>
          <button class="eln-btn-primary lg"><AppIcon name="plus" :size="14" />新建记录</button>
        </div>
      </template>
    </PageHeader>

    <!-- 筛选栏 4:910 -->
    <div class="filter-bar">
      <div class="search-box">
        <AppIcon name="search" :size="15" />
        <input v-model="keyword" placeholder="搜索记录内容 / 关键词" />
      </div>
      <button
        v-for="c in filters"
        :key="c"
        class="chip"
        :class="{ on: activeChip === c }"
        @click="activeChip = c"
      >
        {{ c }}
      </button>
    </div>

    <div class="nb-cols">
      <!-- 左栏-记录流 4:923 -->
      <div class="nb-stream">
        <!-- 指标条 4:925 -->
        <div class="kpi-bar">
          <div v-for="s in notebookStats" :key="s.label" class="kpi">
            <span class="kpi-label">{{ s.label }}</span>
            <span class="kpi-value num" :class="s.tone">{{ s.value }}</span>
          </div>
        </div>

        <!-- 分组头 4:938 -->
        <div v-for="g in notebookGroups" :key="g.name" class="group-head">
          <span class="group-title">{{ g.name }}</span>
          <span class="group-count">{{ g.count }}</span>
        </div>

        <article v-for="r in filtered" :key="r.id" class="record">
          <div class="rec-rail">
            <span class="rec-dot" :class="r.dot"></span>
            <span class="rec-line"></span>
          </div>
          <div class="rec-body">
            <div class="rec-head">
              <span class="rec-author">{{ r.author }}</span>
              <span class="rec-time num">{{ r.date }}</span>
              <span class="rec-type" :class="typeClass(r.type)">{{ r.type }}</span>
            </div>
            <p class="rec-text">{{ r.body }}</p>
            <div class="rec-path">{{ r.path }}</div>
          </div>
        </article>
        <p v-if="filtered.length === 0" class="empty">当前筛选条件下暂无记录</p>
      </div>

      <!-- 右栏-目录统计 4:924 -->
      <aside class="nb-side">
        <!-- 卡片-记录本目录 4:991 -->
        <section class="side-card">
          <h2 class="side-title">记录本目录</h2>
          <div
            v-for="c in notebookCatalog"
            :key="c.name"
            class="cat-row"
            :class="{ child: c.level === 1 }"
          >
            <span class="cat-name" :class="{ strong: c.level === 0 }">{{ c.name }}</span>
            <span class="cat-count num">{{ c.count }}</span>
          </div>
        </section>

        <!-- 卡片-记录类型分布 4:1005 -->
        <section class="side-card">
          <h2 class="side-title">记录类型分布</h2>
          <div v-for="t in notebookTypeDist" :key="t.label" class="dist-row">
            <span class="dist-dot" :style="{ background: t.color }"></span>
            <span class="dist-name">{{ t.label }}</span>
            <span class="dist-value num" :class="t.tone">{{ t.num }}</span>
          </div>
        </section>

        <!-- 卡片-归档导出 4:1023 -->
        <section class="side-card tight">
          <h2 class="side-title">归档与导出</h2>
          <p class="side-note">记录本随任务关闭进入项目归档；未审核记录不参与导出（DEC-003 / DEC-010）</p>
          <button class="link-btn">导出项目记录本（PDF / Excel）</button>
        </section>
      </aside>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import PageHeader from '../components/PageHeader.vue'
import AppIcon from '../components/AppIcon.vue'
import {
  notebookRecords,
  notebookFilters,
  notebookStats,
  notebookGroups,
  notebookCatalog,
  notebookTypeDist
} from '../data/mock'

const filters = notebookFilters
const activeChip = ref('全部')
const keyword = ref('')

const filtered = computed(() =>
  notebookRecords.filter((r) => {
    const byChip = activeChip.value === '全部' || r.type === activeChip.value
    const byKw = !keyword.value || r.body.includes(keyword.value)
    return byChip && byKw
  })
)

// 类型标签配色（画布 4:949 测试数据 / 4:962 异常记录 / 4:1072 结论与评审）
function typeClass(type) {
  if (type === '测试数据') return 'data'
  if (type === '异常记录') return 'error'
  if (type === '结论与评审') return 'review'
  return 'op'
}
</script>

<style scoped>
.notebook {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* ---------- 页头操作组 ---------- */
.head-actions {
  display: flex;
  gap: 10px;
  flex-shrink: 0;
}
.lg {
  height: 38px;
  padding: 0 14px;
  font-size: 13px;
}

/* ---------- 筛选栏 4:910 ---------- */
.filter-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.search-box {
  width: 300px;
  height: 38px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  color: var(--color-placeholder);
  flex-shrink: 0;
}
.search-box input {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: transparent;
}
.search-box input::placeholder {
  color: var(--color-placeholder);
}
.search-box:focus-within {
  border-color: var(--color-primary);
}
.chip {
  height: 34px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-chip);
  background: var(--color-card);
  font-size: 13px;
  color: var(--color-text-menu);
  flex-shrink: 0;
  transition: all 0.12s ease;
}
.chip:hover {
  border-color: var(--color-border-strong);
}
.chip.on {
  background: var(--color-active-bg);
  border-color: transparent;
  color: var(--color-primary);
  font-weight: 500;
}

/* ---------- 记录布局 4:922（gap 16） ---------- */
.nb-cols {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}
.nb-stream {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.nb-side {
  width: 320px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

/* 指标条 4:925（4 卡 pad14 r10） */
.kpi-bar {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
}
.kpi {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 14px;
  background: var(--color-card);
  border-radius: 10px;
}
.kpi-label {
  font-size: 11px;
  color: var(--color-text-secondary);
}
.kpi-value {
  font-size: 22px;
  font-weight: 600;
  color: var(--color-text);
}
.kpi-value.primary {
  color: var(--color-primary);
}
.kpi-value.danger {
  color: #EF4444;
}
.kpi-value.warn {
  color: #F59E0B;
}
.num {
  font-family: var(--font-en);
  font-variant-numeric: tabular-nums;
}

/* 分组头 4:938 */
.group-head {
  display: flex;
  align-items: center;
  gap: 8px;
}
.group-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
}
.group-count {
  font-size: 11px;
  color: var(--color-placeholder);
}

/* 记录卡 4:941（pad16 r10 白底；rail = 圆点 10 + gap6 + 竖线 2×64，4:942/4:943/4:944） */
.record {
  display: flex;
  gap: 12px;
  padding: 16px;
  background: var(--color-card);
  border-radius: 10px;
}
.rec-rail {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}
.rec-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}
.rec-dot.blue {
  background: var(--color-primary);
}
.rec-dot.red {
  background: #EF4444;
}
.rec-dot.purple {
  background: #7C3AED;
}
.rec-line {
  width: 2px;
  height: 64px; /* 画布 4:944 固定高 64（非拉伸填满） */
  flex-shrink: 0;
  background: var(--color-border);
}
.rec-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.rec-head {
  display: flex;
  align-items: center;
  gap: 8px;
}
.rec-author {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.rec-time {
  font-size: 11px;
  color: var(--color-placeholder);
}
.rec-type {
  padding: 4px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 500;
  line-height: 1;
}
.rec-type.op {
  background: #F4F4F5;
  color: var(--color-subtle-text);
}
.rec-type.data {
  background: var(--color-notice-bg);
  color: #92400E;
}
.rec-type.error {
  background: #FEF2F2;
  color: #B91C1C;
}
.rec-type.review {
  background: var(--color-role-bg);
  color: #5B21B6;
}
.rec-text {
  margin: 0;
  font-size: 13px;
  color: var(--color-text-menu);
  line-height: 1.6;
}
.rec-path {
  font-size: 11px;
  color: var(--color-primary);
}
.empty {
  padding: 48px 0;
  text-align: center;
  font-size: 13px;
  color: var(--color-placeholder);
}

/* ---------- 右栏卡片 ---------- */
.side-card {
  padding: 16px;
  background: var(--color-card);
  border-radius: var(--radius-card);
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.side-card.tight {
  gap: 8px;
}
.side-title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.side-note {
  margin: 0;
  font-size: 11px;
  color: var(--color-placeholder);
  line-height: 1.6;
}
.link-btn {
  align-self: flex-start;
  padding: 0;
  border: none;
  background: none;
  font-size: 12px;
  font-weight: 500;
  color: var(--color-primary);
}
.link-btn:hover {
  text-decoration: underline;
}

/* 记录本目录 */
.cat-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.cat-row.child {
  padding: 8px;
}
.cat-name {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-subtle-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cat-name.strong {
  font-weight: 500;
  color: var(--color-text);
}
.cat-count {
  font-size: 11px;
  color: var(--color-placeholder);
  flex-shrink: 0;
}

/* 记录类型分布 */
.dist-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.dist-dot {
  width: 8px;
  height: 8px;
  border-radius: 4px;
  flex-shrink: 0;
}
.dist-name {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-subtle-text);
}
.dist-value {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-menu);
  flex-shrink: 0;
}
.dist-value.danger {
  color: #EF4444;
}
</style>
