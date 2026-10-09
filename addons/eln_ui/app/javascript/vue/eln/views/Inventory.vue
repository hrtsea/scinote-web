<template>
  <!-- 库存台账（画布 79:64 化学品与试剂 / 79:146 设备 / 79:228 新建库存弹窗） -->
  <div class="iv-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">库存</span>
    </div>

    <PageHeader
      title="库存"
      :subtitle="current.subtitle"
      show-navigator
      @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
    />

    <!-- 工具栏 -->
    <div class="iv-toolbar">
      <div class="iv-tool-left">
        <button class="eln-btn-primary" @click="showCreate = true">
          <AppIcon name="plus" :size="14" />新建库存
        </button>
        <button class="eln-btn-ghost">导入</button>
      </div>
      <div class="iv-tool-mid">
        <button class="iv-select">
          {{ current.label }}
          <AppIcon name="chevron-down" :size="14" />
        </button>
        <button class="iv-select" :class="{ on: alertOnly }" @click="alertOnly = !alertOnly">
          仅看活动提醒
        </button>
      </div>
      <div class="iv-tool-right">
        <button class="eln-btn-ghost">管理列</button>
        <button class="eln-icon-btn" title="搜索"><AppIcon name="search" :size="16" /></button>
      </div>
    </div>

    <!-- 主区：左库存列表 220 + 右表 -->
    <div class="iv-main">
      <aside class="iv-side">
        <div class="iv-side-title">库存列表</div>
        <p class="iv-side-note">创建库存后显示于此，可在库存间快速跳转</p>
        <button
          v-for="t in invTypes"
          :key="t.key"
          class="iv-item"
          :class="{ on: activeType === t.key }"
          @click="activeType = t.key"
        >{{ t.label }}</button>
        <div class="iv-side-spacer"></div>
        <div class="iv-side-foot">模板：{{ current.label }} · {{ current.cols }} 列</div>
      </aside>

      <div class="iv-card">
        <table v-if="current.rows" class="eln-table">
          <thead>
            <tr>
              <th class="eln-th">名称</th>
              <template v-if="activeType === 'chemicals'">
                <th class="eln-th" style="width:110px">库存</th>
                <th class="eln-th" style="width:90px">类型</th>
                <th class="eln-th" style="width:110px">过期日期</th>
                <th class="eln-th" style="width:120px">CAS 号</th>
                <th class="eln-th" style="width:90px">安全数据表</th>
              </template>
              <template v-else>
                <th class="eln-th" style="width:120px">校准日期</th>
                <th class="eln-th" style="width:110px">可用状态</th>
                <th class="eln-th" style="width:130px">生产厂商</th>
                <th class="eln-th" style="width:130px">序列号</th>
                <th class="eln-th" style="width:90px">联系人</th>
              </template>
              <th class="eln-th" style="width:40px"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in current.rows" :key="r.name">
              <td class="eln-td iv-strong">{{ r.name }}</td>
              <template v-if="activeType === 'chemicals'">
                <td class="eln-td" :class="r.stockClass">{{ r.stock }}</td>
                <td class="eln-td">{{ r.c2 }}</td>
                <td class="eln-td" :class="r.c3Class">{{ r.c3 }}</td>
                <td class="eln-td">{{ r.c4 }}</td>
                <td class="eln-td"><span class="iv-link">查看</span></td>
              </template>
              <template v-else>
                <td class="eln-td" :class="r.stockClass">{{ r.stock }}</td>
                <td class="eln-td iv-strong" :class="r.stateClass">{{ r.state }}</td>
                <td class="eln-td">{{ r.c2 }}</td>
                <td class="eln-td">{{ r.c3 }}</td>
                <td class="eln-td">{{ r.c4 }}</td>
              </template>
              <td class="eln-td iv-more">⋯</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="iv-empty">
          <AppIcon name="archive" :size="28" />
          <p>「{{ current.label }}」库存尚未创建</p>
          <span>原生 4 套预置模板在团队创建时自动生成，库存须由用户显式新建后才会出现在此列表。</span>
        </div>
        <div v-if="current.foot" class="iv-card-foot">{{ current.foot }}</div>
      </div>
    </div>

    <!-- ===== MODAL-NEW-INVENTORY 新建库存（选择模板） ===== -->
    <div v-if="showCreate" class="iv-mask" @click.self="showCreate = false">
      <div class="iv-modal">
        <div class="iv-modal-title">创建库存</div>

        <div class="iv-field">
          <label class="iv-label">库存名称</label>
          <input class="iv-input" v-model="newName" placeholder="我的库存" />
        </div>

        <div class="iv-field">
          <label class="iv-label">选择库存模板</label>
          <div class="iv-select-box">
            <select class="iv-native-select" v-model="newTemplate">
              <option v-for="t in invTypes" :key="t.key" :value="t.templateName">{{ t.templateName }}</option>
            </select>
            <AppIcon name="chevron-down" :size="14" />
          </div>
          <p class="iv-hint">每个库存按所选模板拥有各自一套列；共 4 套预置模板（默认 / 细胞系 / 设备 / 化学品与试剂）</p>
        </div>

        <div class="iv-preview">
          <template v-if="newTemplate === '化学品与试剂模板'">
            <div class="iv-preview-title">模板列预览 · 化学品与试剂（14 列）</div>
            <div v-for="l in chemicalsPreview" :key="l.text" class="iv-preview-line" :class="{ dim: l.dim }">{{ l.text }}</div>
          </template>
          <template v-else>
            <div class="iv-preview-title">模板列预览 · {{ newTemplate.replace('模板', '') }}</div>
            <div class="iv-preview-line dim">
              列定义取自 RepositoryTemplate.column_definitions；本原型仅展开「化学品与试剂」的完整列预览。
            </div>
          </template>
        </div>

        <div class="iv-modal-foot">
          <button class="eln-btn-ghost" @click="showCreate = false">取消</button>
          <button class="eln-btn-primary" @click="showCreate = false">创建</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'

const activeType = ref('chemicals')
const alertOnly = ref(false)
const showCreate = ref(false)
const newName = ref('')
const newTemplate = ref('化学品与试剂模板')

const chemicalsPreview = [
  { text: '浓度 · 文本' },
  { text: '库存 · Stock（含单位与低库存提醒）' },
  { text: '开封日期 / 过期日期 · 日期（28 天提醒）' },
  { text: '存储条件 / 类型 · 列表' },
  { text: 'CAS 号 / 安全数据表（MSDS 附件）' },
  { text: '价格 · 文本列（非金额，花费核算走 unit_price 快照）', dim: true }
]

const invTypes = [
  {
    key: 'chemicals',
    label: '化学品与试剂',
    templateName: '化学品与试剂模板',
    cols: 14,
    subtitle: '化学品与试剂模板 · 团队创建即自动获得 4 套预置模板（默认 / 细胞系 / 设备 / 化学品与试剂）',
    foot: '共 3 项 · 价格列为文本列（非金额），花费核算走 RepositoryRow.unit_price 快照（SCN-RES-COST-1）',
    rows: [
      { name: 'PP 基料 K8003', stock: '120 kg', c2: '固体', c3: '2027-06-30', c4: '9010-79-1' },
      { name: 'POE 增韧剂 8150', stock: '45 kg', c2: '固体', c3: '2026-12-15', c3Class: 'iv-orange', c4: '26221-27-2' },
      { name: '滑石粉 TYT-777A', stock: '8 kg · 低库存', stockClass: 'iv-red iv-strong', c2: '固体', c3: '2028-01-31', c4: '14807-96-6' }
    ]
  },
  {
    key: 'equipment',
    label: '设备',
    templateName: '设备模板',
    cols: 10,
    subtitle: '设备模板 · 10 列 · 不含 Stock 列，按「可用状态」管理；不计入项目花费（SCN-RES-COST-6）',
    foot: '共 3 项 · 校准日期带 28 天提醒「请考虑重新校准」· 设备库存不计入项目花费（SCN-RES-COST-6）',
    rows: [
      { name: '万能材料试验机 5967', stock: '2026-03-10', state: '● 可使用', stateClass: 'iv-green', c2: 'Instron', c3: 'IN-5967-01', c4: '张伟' },
      { name: '差示扫描量热仪 DSC 214', stock: '2026-09-05', stockClass: 'iv-orange iv-strong', state: '● 使用中', stateClass: 'iv-red', c2: 'NETZSCH', c3: 'DSC214-08', c4: '李娜' },
      { name: '恒温恒湿箱 LHS-150HC', stock: '2026-08-20', state: '● 维护中', stateClass: 'iv-orange', c2: '上海一恒', c3: 'LHS-150HC-02', c4: '王强' }
    ]
  },
  {
    key: 'samples',
    label: '样品',
    templateName: '默认模板',
    cols: 0,
    subtitle: '该库存类型未在画布中展开数据，仅保留入口（原生 4 套预置模板之一）',
    rows: null
  },
  {
    key: 'celllines',
    label: '细胞系',
    templateName: '细胞系模板',
    cols: 0,
    subtitle: '该库存类型未在画布中展开数据，仅保留入口（原生 4 套预置模板之一）',
    rows: null
  }
]

const current = computed(() => invTypes.find(t => t.key === activeType.value))
</script>

<style scoped>
.iv-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:67 内容区 gap 16 */
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

/* 工具栏 */
.iv-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
}
.iv-tool-left,
.iv-tool-mid,
.iv-tool-right {
  display: flex;
  align-items: center;
  gap: 8px;
}
.iv-tool-right {
  margin-left: auto;
}
.iv-select {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  color: var(--color-subtle-text);
}
.iv-select:hover {
  border-color: var(--color-border-strong);
}
.iv-select.on {
  background: var(--color-active-bg);
  border-color: var(--color-primary);
  color: var(--color-primary);
}

/* 主区 */
.iv-main {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}
.iv-side {
  width: 220px;
  flex-shrink: 0;
  min-height: 420px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 14px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
}
.iv-side-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
}
.iv-side-note {
  margin: -4px 0 2px;
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-placeholder);
}
.iv-item {
  height: 32px;
  padding: 0 10px;
  background: none;
  border: none;
  border-radius: 6px;
  text-align: left;
  font-size: 13px;
  color: var(--color-text-menu);
  transition: background 0.15s ease, color 0.15s ease;
}
.iv-item:hover {
  background: var(--color-fill-soft);
}
.iv-item.on {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}
.iv-side-spacer {
  flex: 1;
}
.iv-side-foot {
  font-size: 11px;
  color: var(--color-placeholder);
}

.iv-card {
  flex: 1;
  min-width: 0;
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.iv-card-foot {
  padding: 12px 20px 16px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
}
.iv-empty {
  padding: 56px 24px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  color: var(--color-placeholder);
  text-align: center;
}
.iv-empty p {
  margin: 0;
  font-size: 13px;
  color: var(--color-text-secondary);
}
.iv-empty span {
  max-width: 420px;
  font-size: 11px;
  line-height: 1.7;
}

/* 文本色 */
.iv-strong {
  font-weight: 500;
}
.iv-more {
  color: var(--color-text-secondary);
  text-align: center;
}
.iv-link {
  color: var(--color-primary);
  cursor: pointer;
}
.iv-link:hover {
  text-decoration: underline;
}
.iv-red {
  color: #DF3562;
}
.iv-orange {
  color: #E9A845;
}
.iv-green {
  color: var(--status-done);
}

/* ===== 弹窗 ===== */
.iv-mask {
  position: fixed;
  inset: 0;
  background: rgba(10, 10, 11, 0.32);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 60;
  padding: 24px;
}
.iv-modal {
  width: 480px;
  max-height: 90vh;
  overflow-y: auto;
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: 0 18px 40px -12px rgba(10, 10, 11, 0.1);
  padding: 24px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.iv-modal-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--color-text);
}
.iv-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.iv-label {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-secondary);
}
.iv-input,
.iv-native-select {
  width: 100%;
  height: 38px;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  outline: none;
}
.iv-input::placeholder {
  color: var(--color-placeholder);
}
.iv-input:focus,
.iv-native-select:focus {
  border-color: var(--color-primary);
}
.iv-select-box {
  position: relative;
  display: flex;
  align-items: center;
  color: var(--color-text-secondary);
}
.iv-select-box .iv-native-select {
  appearance: none;
  padding-right: 34px;
}
.iv-select-box :deep(svg) {
  position: absolute;
  right: 12px;
  pointer-events: none;
}
.iv-hint {
  margin: 0;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
}
.iv-preview {
  background: #FAFAFA;
  border-radius: 8px;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.iv-preview-title {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-subtle-text);
}
.iv-preview-line {
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-subtle-text);
}
.iv-preview-line.dim {
  color: var(--color-placeholder);
}
.iv-modal-foot {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
</style>
