<template>
  <!-- 资源基础档案（画布 79:944 / PRD §7.9.4）：双 Tab（材料档案 / 测试表征服务档案），仅单位管理员 -->
  <div class="archive-page">
    <!-- 面包屑 -->
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/admin" class="crumb-link">系统管理</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">资源基础档案</span>
    </div>

    <!-- 页头 -->
    <div class="ra-head">
      <PageHeader
        title="资源基础档案"
        subtitle="全局资源目录 · 材料档案与测试表征服务档案的唯一维护入口（REQ-RES-ARCHIVE）"
        show-navigator
        @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
      />
      <div class="ra-head-note">仅单位管理员可维护 · 其他角色不提供入口，直接访问拒绝并提示无权限（SCN-RES-ARCHIVE-1/2）</div>
    </div>

    <!-- 工具栏 -->
    <div class="ra-toolbar">
      <div class="ra-actions">
        <button class="eln-btn-primary"><AppIcon name="plus" :size="14" />新建材料档案</button>
        <button class="eln-btn-ghost">新建服务档案</button>
        <button class="eln-btn-ghost">批量导入</button>
      </div>
      <div class="ra-right">
        <div class="ra-search">
          <AppIcon name="search" :size="14" />
          <input placeholder="搜索名称 / 规格 / 供应商 / 服务商…" v-model="keyword" />
        </div>
        <button class="eln-btn-ghost">导出档案</button>
        <button class="eln-btn-ghost">管理列</button>
      </div>
    </div>

    <!-- 页签条 -->
    <div class="ra-tabs">
      <button
        class="ra-tab"
        :class="{ active: activeTab === 'material' }"
        @click="activeTab = 'material'"
      >材料档案</button>
      <button
        class="ra-tab"
        :class="{ active: activeTab === 'service' }"
        @click="activeTab = 'service'"
      >测试表征服务档案</button>
    </div>

    <!-- ===== 面板：材料档案 ===== -->
    <div v-if="activeTab === 'material'" class="ra-panel eln-card">
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th">材料名称</th>
            <th class="eln-th">规格</th>
            <th class="eln-th">单价（采购基准）</th>
            <th class="eln-th">库存</th>
            <th class="eln-th">供应商</th>
            <th class="eln-th">存放位置</th>
            <th class="eln-th"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="m in filteredMaterials" :key="m.name">
            <td class="eln-td ra-strong">{{ m.name }}</td>
            <td class="eln-td">{{ m.spec }}</td>
            <td class="eln-td">{{ m.price }}</td>
            <td class="eln-td" :class="m.stockClass">{{ m.stock }}</td>
            <td class="eln-td">{{ m.vendor }}</td>
            <td class="eln-td">
              <span v-if="m.location" class="ra-link">{{ m.location }}</span>
              <span v-else class="ra-muted">位置待定</span>
            </td>
            <td class="eln-td ra-more">⋯</td>
          </tr>
        </tbody>
      </table>
      <div class="ra-footnote">
        共 5 项 · 单价为采购基准价，任务消耗出库时快照至 RepositoryLedgerRecord.unit_price（§7.21）；
        「存放位置」为可点击引用，下钻至 Item locations 位置列表页（SCN-LOC-AUDIT-4）；且设备模板
        （RepositoryTemplate.equipment）创建的库存不在本档案维护，且三门径均不计入项目花费（SCN-RES-COST-6）。
      </div>
    </div>

    <!-- ===== 面板：测试表征服务档案 ===== -->
    <div v-else class="ra-panel eln-card">
      <div class="ra-hint">
        服务档案是测试表征服务的唯一载体：服务不建库存条目、不设 Stock 额度（V1.21）——终审通过即获执行许可，
        执行完成在「消耗/执行明细表」登记服务行，单价取本档案快照。
      </div>
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th">测试项目</th>
            <th class="eln-th">单价（快照来源）</th>
            <th class="eln-th">周期</th>
            <th class="eln-th">服务商</th>
            <th class="eln-th">是否需验收（requires_acceptance）</th>
            <th class="eln-th"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in filteredServices" :key="s.name">
            <td class="eln-td ra-strong">{{ s.name }}</td>
            <td class="eln-td">{{ s.price }}</td>
            <td class="eln-td">{{ s.cycle }}</td>
            <td class="eln-td">{{ s.vendor }}</td>
            <td class="eln-td">
              <span class="ra-chip" :class="s.acceptance ? 'ra-chip-purple' : 'ra-chip-grey'">
                {{ s.acceptance ? '需验收' : '不需验收' }}
              </span>
            </td>
            <td class="eln-td ra-more">⋯</td>
          </tr>
        </tbody>
      </table>
      <div class="ra-footnote">
        共 4 项 · 服务档案不产生库存条目 / Stock 额度 / Ledger 行（V1.21）；「需验收」默认开启（requires_acceptance），
        置为「不需验收」时执行完成即计入花费；验收闸门与逾期封禁复用原生 MyModuleStatusConsequence
        （§7.23 / §7.24，SCN-RES-TEST-1~4 · SCN-RES-TEST-STRIKE-1~4）。
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'

const activeTab = ref('material')
const keyword = ref('')

const materials = [
  { name: 'PP 基料 T30S', spec: '25kg/袋', price: '¥11.20/kg', stock: '120 kg', vendor: '中石化华东', location: '化学品柜 A·' },
  { name: 'POE 8150', spec: '20kg/袋', price: '¥18.60/kg', stock: '45 kg', vendor: '陶氏化学', location: '化学品柜 A·' },
  { name: '滑石粉 TYT-777A', spec: '25kg/袋', price: '¥2.80/kg', stock: '8 kg · 低库存', stockClass: 'ra-danger', vendor: '辽宁艾海', location: '原料盒 A1·' },
  { name: '相容剂 PP-g-MAH', spec: '20kg/袋', price: '¥32.00/kg', stock: '26 kg', vendor: '佳易容', location: '化学品柜 B·' },
  { name: '硅烷偶联剂 KH-550', spec: '5kg/桶', price: '¥46.00/kg', stock: '—（未入库）', stockClass: 'ra-muted', vendor: '南京曙光', location: '' }
]

const services = [
  { name: '拉伸强度测试', price: '¥120 / 次', cycle: '3 个工作日', vendor: '上海化工研究院', acceptance: true },
  { name: '冲击强度（悬臂梁）测试', price: '¥150 / 次', cycle: '3 个工作日', vendor: '上海化工研究院', acceptance: true },
  { name: 'DSC 差示扫描量热', price: '¥200 / 次', cycle: '5 个工作日', vendor: '长春应化所', acceptance: true },
  { name: '熔融指数（MFR）测试', price: '¥80 / 次', cycle: '2 个工作日', vendor: '长春应化所', acceptance: false }
]

const filteredMaterials = computed(() => {
  const k = keyword.value.trim().toLowerCase()
  if (!k) return materials
  return materials.filter(m =>
    m.name.toLowerCase().includes(k) || m.spec.toLowerCase().includes(k) || m.vendor.toLowerCase().includes(k)
  )
})
const filteredServices = computed(() => {
  const k = keyword.value.trim().toLowerCase()
  if (!k) return services
  return services.filter(s =>
    s.name.toLowerCase().includes(k) || s.vendor.toLowerCase().includes(k)
  )
})
</script>

<style scoped>
.archive-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:947 内容区 gap 16 */
}
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
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
.ra-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.ra-head-note {
  max-width: 380px;
  font-size: 12px;
  color: var(--color-placeholder); /* 画布 79:955 权限提示 #A1A1AA */
  text-align: right;
  line-height: 1.6;
  padding-top: 4px;
}

/* 工具栏 */
.ra-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}
.ra-actions {
  display: flex;
  gap: 8px;
}
.ra-right {
  display: flex;
  gap: 8px;
  flex: 1;
  max-width: 560px;
}
.ra-search {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-card);
  color: var(--color-text-secondary);
}
.ra-search input {
  flex: 1;
  border: none;
  outline: none;
  background: none;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
}

/* 页签条 */
.ra-tabs {
  display: flex;
  gap: 4px;
  padding: 6px;
}
.ra-tab {
  height: 32px;
  padding: 0 16px;
  background: none;
  border: none;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-subtle-text);
  transition: background 0.15s ease, color 0.15s ease;
}
.ra-tab:hover {
  background: var(--color-fill-soft);
  color: var(--color-text);
}
.ra-tab.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}

/* 面板（画布 79:947 区：表格卡片 padding=0，内缩下沉到表格单元格；卡首 hint 与卡尾提示自带外边距） */
.ra-panel {
  padding: 0;
  overflow: hidden;
}
.ra-hint {
  background: var(--color-role-bg);
  color: var(--color-role-text);
  font-size: 12px;
  line-height: 1.7;
  padding: 12px 16px;
  border-radius: var(--radius-small);
  margin: 16px 20px 14px;
}
.ra-strong {
  font-weight: 500;
}
.ra-link {
  color: var(--color-primary);
  cursor: pointer;
}
.ra-link:hover {
  text-decoration: underline;
}
.ra-danger {
  color: #DF3562;
}
.ra-muted {
  color: var(--color-placeholder);
}
.ra-more {
  color: var(--color-text-secondary);
  text-align: center;
}
.ra-chip {
  display: inline-flex;
  align-items: center;
  height: 22px;
  padding: 0 10px;
  border-radius: var(--radius-chip);
  font-size: 11px;
}
.ra-chip-purple {
  background: var(--color-role-bg);
  color: var(--color-role-text);
}
.ra-chip-grey {
  background: var(--color-fill-soft);
  color: var(--color-text-secondary);
}
.ra-footnote {
  margin: 12px 20px 14px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
  background: var(--color-fill-soft);
  border-radius: var(--radius-small);
  padding: 10px 14px;
}
</style>
