<template>
  <!-- 盒子详情（画布 79:639 / PRD §7.15 · DEC-016/017）：三页签独立面板 -->
  <div class="ld-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/locations" class="crumb-link">位置</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/locations" class="crumb-link">化学品柜 A</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">原料盒 A1</span>
    </div>

    <!-- 页头 -->
    <div class="ld-head">
      <div class="ld-head-left">
        <!-- 导航器开关（画布 79:645） -->
        <button
          class="eln-icon-btn"
          title="导航器"
          @click="ui.navigatorOpen ? closeNavigator() : openNavigator()"
        >
          <AppIcon name="navigator" :size="16" />
        </button>
        <div class="ld-thumb" title="盒图（png / jpg）">
          <AppIcon name="layout" :size="20" />
        </div>
        <div class="ld-titles">
          <h1 class="ld-title">原料盒 A1</h1>
          <p class="ld-meta">
            SL-A02-1 · 网格盒 dimensions=[3,6] · 已用 4 / 18 格（含 1 格锁定不可见） · 建盒人 王强 · 2026-04-02
          </p>
        </div>
      </div>
      <div class="ld-head-actions">
        <button class="eln-btn-ghost">Image (png/jpg)</button>
        <button class="eln-btn-ghost" disabled title="仅空盒可用">变更尺寸（仅空盒可用）</button>
      </div>
    </div>

    <!-- 二级 Tab（原生视图 + 自研「出入库记录」） -->
    <div class="ld-tabs">
      <button class="ld-tab" :class="{ active: activeTab === 'grid' }" @click="activeTab = 'grid'">Grid</button>
      <button class="ld-tab" :class="{ active: activeTab === 'items' }" @click="activeTab = 'items'">Items</button>
      <button class="ld-tab" :class="{ active: activeTab === 'ledger' }" @click="activeTab = 'ledger'">出入库记录</button>
    </div>

    <!-- ============ Grid 网格视图 ============ -->
    <div v-if="activeTab === 'grid'" class="ld-card">
      <div class="ld-card-head">
        <h3 class="ld-card-title">Grid 网格视图</h3>
        <span class="ld-card-note">
          Position = 行字母 + 列号（A1 = 第 1 行第 1 列）；已占用格标 occupied，空位可点击指派；同一位置不得被两个物品占用（SCN-LOC-CONTAINER-1/2）
        </span>
      </div>
      <div class="ld-grid-wrap">
        <div class="ld-grid">
          <div class="ld-grid-corner"></div>
          <div v-for="c in cols" :key="`c${c}`" class="ld-grid-col">{{ c }}</div>
          <template v-for="(row, ri) in gridRows" :key="`r${ri}`">
            <div class="ld-grid-row">{{ rowLetter(ri) }}</div>
            <div
              v-for="(cell, ci) in row"
              :key="cell.pos"
              class="ld-cell"
              :class="cellClasses(cell)"
              :title="cell.state === 'locked' ? '已占用但内容不可见' : cell.name || '空位，可点击指派'"
            >
              <template v-if="cell.state === 'occupied'">
                <div class="ld-cell-pos">{{ cell.pos }}</div>
                <div class="ld-cell-name" :class="{ low: cell.low }">{{ cell.name }}</div>
              </template>
              <template v-else-if="cell.state === 'locked'">
                <div class="ld-cell-pos">{{ cell.pos }} · 锁定</div>
                <div class="ld-cell-name locked">
                  <AppIcon name="lock" :size="11" /> Private item
                </div>
              </template>
            </div>
          </template>
        </div>
      </div>
      <div class="ld-card-foot">
        空位可点击指派（data-locempty）；C5 为该格已被占用但当前用户不可见——仍占位并呈锁定态（斜纹底 + 锁标识 + Private item），
        不输出 data-locempty、不泄露物品名与编号（SCN-LOC-CONTAINER-9）。网格盒内位置唯一：同格重复指派由前端 locItemAt 校验拒绝、
        服务端 ensure_uniq_position 兜底（SCN-LOC-CONTAINER-2）。网格盒内位置必填（position_must_be_present，SCN-LOC-CONTAINER-7）。
      </div>
    </div>

    <!-- ============ Items 盒内物品清单 ============ -->
    <div v-else-if="activeTab === 'items'" class="ld-card">
      <div class="ld-card-head">
        <h3 class="ld-card-title">Items 盒内物品清单</h3>
        <span class="ld-card-note">
          原生列：Position / Reminders / Item ID / Name / Stock；行内自研「申请领用」走既有二段式审批，不另造审批流（REQ-LOC-AUDIT · SCN-LOC-AUDIT-3）
        </span>
      </div>
      <div class="ld-items-bar">
        <div class="ld-items-actions">
          <button class="eln-btn-primary"><AppIcon name="plus" :size="14" />Assign item</button>
          <button class="eln-btn-ghost">Unassign</button>
          <button class="eln-btn-ghost">Move</button>
        </div>
        <button class="eln-btn-ghost">导出当前盒子</button>
      </div>
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th" style="width:90px">Position</th>
            <th class="eln-th" style="width:110px">Reminders</th>
            <th class="eln-th" style="width:130px">Item ID</th>
            <th class="eln-th">Name</th>
            <th class="eln-th" style="width:150px">Stock</th>
            <th class="eln-th" style="width:100px">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="it in items" :key="it.id">
            <td class="eln-td ld-strong">{{ it.pos }}</td>
            <td class="eln-td">
              <span v-if="it.reminder === '—'" class="ld-muted">{{ it.reminder }}</span>
              <span v-else class="ld-orange ld-strong">{{ it.reminder }}</span>
            </td>
            <td class="eln-td ld-mono">{{ it.id }}</td>
            <td class="eln-td ld-strong">{{ it.name }}</td>
            <td class="eln-td" :class="it.low ? 'ld-red ld-strong' : ''">{{ it.stock }}</td>
            <td class="eln-td"><span class="ld-link">申请领用</span></td>
          </tr>
        </tbody>
      </table>
      <div class="ld-card-foot">
        共 3 件 · 逐角色：单位管理员／项目负责人／小组组长可见 Assign / Unassign / Move；组员盒内只读（出现 STATE-LOC-LOCK 占位）
        但仍可见并可用「申请领用」；越权调用走 showNoPerm（REQ-LOC-AUDIT）。出库扣减与位置解除默认不自动联动（DEC-017 / 待确认 F）
        ——仅整件领用／报废场景由用户显式勾选「同时解除位置指派」，默认不勾选。
      </div>
    </div>

    <!-- ============ 出入库记录（自研二级 Tab） ============ -->
    <div v-else class="ld-card">
      <div class="ld-card-head">
        <h3 class="ld-card-title">出入库记录</h3>
        <span class="ld-card-note">
          与左栏 Global activities 同源（团队级事件流按位置维度过滤的同一份数据视图，不另存第二份事件）；记录不可删除且无删除入口（REQ-NFR · SCN-LOC-AUDIT-2/9）
        </span>
      </div>
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th" style="width:150px">时间</th>
            <th class="eln-th" style="width:100px">操作人</th>
            <th class="eln-th">物品</th>
            <th class="eln-th" style="width:130px">位置</th>
            <th class="eln-th" style="width:120px">动作类型</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="l in ledger" :key="l.time">
            <td class="eln-td">{{ l.time }}</td>
            <td class="eln-td">{{ l.user }}</td>
            <td class="eln-td">{{ l.item }}</td>
            <td class="eln-td ld-mono">{{ l.loc }}</td>
            <td class="eln-td ld-strong" :class="actionColor(l.action)">{{ l.action }}</td>
          </tr>
        </tbody>
      </table>
      <div class="ld-card-foot">
        共 4 条 · 动作类型按 DEC-017 决定 3 分为 指派 / 物理移位 / 账目出库，不混为一类流水；指派、解除指派、移位后自动追加一条记录；
        本表为同一份团队级事件流的过滤视图（locLedgerView()），新增事件一律写回 DEMO.activity（locAddLedger()），不另存第二份数据。
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'

const activeTab = ref('grid')
const cols = [1, 2, 3, 4, 5, 6]

function rowLetter(i) {
  return String.fromCharCode(65 + i)
}

const occupied = {
  A1: { name: 'PP 基料 K8003' },
  B3: { name: 'POE 增韧剂 8150' },
  C3: { name: '滑石粉 TYT-777A', low: true },
  C5: { locked: true }
}

// 网格盒 dimensions = [3 行, 6 列]（行字母 A..C、列号 1..6）
const gridRows = [0, 1, 2].map(ri =>
  cols.map((_, ci) => {
    const pos = rowLetter(ri) + (ci + 1)
    const o = occupied[pos]
    if (!o) return { pos, state: 'empty' }
    if (o.locked) return { pos, state: 'locked' }
    return { pos, state: 'occupied', name: o.name, low: o.low }
  })
)

function cellClasses(cell) {
  return {
    occupied: cell.state === 'occupied',
    locked: cell.state === 'locked',
    empty: cell.state === 'empty'
  }
}

const items = [
  { pos: 'A1', reminder: '—', id: 'IT-001284', name: 'PP 基料 K8003', stock: '120 kg' },
  { pos: 'B3', reminder: '临期', id: 'IT-002011', name: 'POE 增韧剂 8150', stock: '45 kg' },
  { pos: 'C3', reminder: '—', id: 'IT-003442', name: '滑石粉 TYT-777A', stock: '8 kg · 低库存', low: true }
]

const ledger = [
  { time: '2026-09-12 10:24', user: '张伟', item: 'PP 基料 K8003（IT-001284）', loc: 'A1', action: '账目出库' },
  { time: '2026-09-10 14:05', user: '张伟', item: '滑石粉 TYT-777A（IT-003442）', loc: 'C3', action: '指派' },
  { time: '2026-09-08 09:30', user: '李娜', item: 'POE 增韧剂 8150（IT-002011）', loc: 'B4 → B3', action: '物理移位' },
  { time: '2026-09-02 16:30', user: '王强', item: 'PP 基料 K8003（IT-001284）', loc: 'A1', action: '指派' }
]

function actionColor(a) {
  if (a === '账目出库') return 'ld-red'
  if (a === '物理移位') return 'ld-orange'
  return 'ld-blue'
}
</script>

<style scoped>
.ld-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:642 内容区 gap 16 */
}
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  flex-wrap: wrap;
}
.crumb-link {
  color: var(--color-placeholder);
  text-decoration: none;
}
.crumb-link:hover {
  color: var(--color-primary);
}
.crumb-current {
  color: var(--color-placeholder);
  font-weight: 400;
}
.crumb-sep {
  color: var(--color-placeholder);
}

/* 页头 */
.ld-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.ld-head-left {
  display: flex;
  align-items: center;
  gap: 16px; /* 画布 79:644 页头 gap 16 */
}
.ld-thumb {
  width: 48px;
  height: 48px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--color-fill-soft);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  color: var(--color-placeholder);
}
.ld-title {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.ld-meta {
  margin: 4px 0 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.ld-head-actions {
  display: flex;
  gap: 8px;
}
.ld-head-actions button[disabled] {
  background: var(--color-fill-soft);
  color: var(--color-placeholder);
  cursor: not-allowed;
}

/* 二级 Tab（下划线） */
.ld-tabs {
  display: flex;
  gap: 28px;
  border-bottom: 1px solid var(--color-border);
}
.ld-tab {
  padding: 8px 0 10px;
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
  font-size: 13px;
  color: var(--color-text-secondary);
}
.ld-tab:hover {
  color: var(--color-text);
}
.ld-tab.active {
  color: var(--color-primary);
  border-bottom-color: var(--color-primary);
  font-weight: 500;
}

/* 卡片 */
.ld-card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.ld-card-head {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 14px 20px;
}
.ld-card-title {
  margin: 0;
  font-size: 15px;
  font-weight: 500;
  color: var(--color-text);
  white-space: nowrap;
}
.ld-card-note {
  font-size: 12px;
  line-height: 1.6;
  color: var(--color-text-secondary);
}
.ld-card-foot {
  padding: 10px 20px 14px;
  font-size: 11px;
  line-height: 1.8;
  color: var(--color-placeholder);
}

/* 网格 */
.ld-grid-wrap {
  padding: 14px 20px 18px;
  border-top: 1px solid var(--color-border);
}
.ld-grid {
  display: grid;
  grid-template-columns: 24px repeat(6, 1fr);
  gap: 6px;
}
.ld-grid-col {
  height: 18px;
  font-size: 11px;
  color: var(--color-placeholder);
  text-align: center;
}
.ld-grid-row {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  color: var(--color-placeholder);
}
.ld-cell {
  height: 44px;
  padding: 4px 8px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 2px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  background: var(--color-card);
  overflow: hidden;
}
.ld-cell.empty:hover {
  border-color: var(--color-primary);
  cursor: pointer;
}
.ld-cell.occupied {
  background: var(--color-active-bg);
  border-color: #BFDBFE;
  cursor: pointer;
}
.ld-cell.locked {
  background: repeating-linear-gradient(
    45deg,
    #F4F4F5,
    #F4F4F5 4px,
    #EAEAEE 4px,
    #EAEAEE 8px
  );
  border: 1px dashed var(--color-border-strong);
  cursor: not-allowed;
}
.ld-cell-pos {
  font-size: 11px;
  color: var(--color-primary);
  font-weight: 500;
}
.ld-cell.locked .ld-cell-pos {
  color: var(--color-placeholder);
}
.ld-cell-name {
  font-size: 11px;
  line-height: 1.3;
  color: var(--color-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ld-cell-name.low {
  color: #DF3562;
}
.ld-cell-name.locked {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--color-placeholder);
}

/* Items 工具条 */
.ld-items-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 0 20px 14px;
}
.ld-items-actions {
  display: flex;
  gap: 8px;
}

/* 文本色 */
.ld-strong {
  font-weight: 500;
}
.ld-mono {
  font-family: var(--font-en);
}
.ld-muted {
  color: var(--color-placeholder);
}
.ld-blue {
  color: var(--color-primary);
}
.ld-red {
  color: #DF3562;
}
.ld-orange {
  color: #E9A845;
}
.ld-link {
  color: var(--color-primary);
  cursor: pointer;
}
.ld-link:hover {
  text-decoration: underline;
}
</style>
