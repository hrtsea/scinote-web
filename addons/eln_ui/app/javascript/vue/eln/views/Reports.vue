<template>
  <!-- 报表中心（画布 79:1214 / PRD §7.11）：四类业务报表，四页签独立面板切换 -->
  <div class="report-page">
    <!-- 面包屑 -->
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">报表中心</span>
    </div>

    <!-- 页头 -->
    <div class="rp-head">
      <PageHeader
        title="报表中心"
        subtitle="四类业务报表 · 项目花费 / AI Token 消耗（云版）/ 项目指标完成统计 / 实验设计迭代统计（REQ-REPORT）"
        show-navigator
        @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
      />
      <div class="rp-head-note">
        当前角色：项目负责人 · 可查看并导出 Excel / PDF（SCN-REPORT-3）；组员为只读，导出按钮隐藏（SCN-REPORT-4）
      </div>
    </div>

    <!-- 工具栏：筛选 + 导出 -->
    <div class="rp-toolbar">
      <div class="rp-filters">
        <button class="rp-chip" v-for="f in filters" :key="f.label">
          {{ f.value }} <span class="rp-caret">▾</span>
        </button>
      </div>
      <div class="rp-export">
        <button class="eln-btn-primary"><AppIcon name="download" :size="14" />导出 Excel</button>
        <button class="eln-btn-ghost">导出 PDF</button>
      </div>
    </div>

    <!-- 页签条 -->
    <div class="rp-tabs">
      <button
        v-for="t in tabs"
        :key="t.key"
        class="rp-tab"
        :class="{ active: activeTab === t.key }"
        @click="activeTab = t.key"
      >
        {{ t.label }}
      </button>
    </div>

    <!-- ===== 面板 1：项目花费报表 ===== -->
    <div v-if="activeTab === 'cost'" class="rp-panel">
      <div class="rp-stat-row">
        <div class="rp-stat eln-card" v-for="s in costStats" :key="s.label">
          <div class="rp-stat-label">{{ s.label }}</div>
          <div class="rp-stat-value">{{ s.value }}</div>
        </div>
      </div>

      <div class="rp-card eln-card">
        <div class="rp-card-head">
          <div class="rp-card-title">
            项目花费报表
            <span class="rp-card-sub">
              出库口径：任务消耗（RepositoryLedgerRecord，快照单价）· 服务口径：验收通过后计入
            </span>
          </div>
          <div class="rp-dim">
            <button
              v-for="d in dims"
              :key="d"
              class="rp-dim-btn"
              :class="{ active: costDim === d }"
              @click="costDim = d"
            >{{ d }}</button>
          </div>
        </div>
        <table class="eln-table">
          <thead>
            <tr>
              <th class="eln-th">项目</th>
              <th class="eln-th">材料花费</th>
              <th class="eln-th">测试表征花费</th>
              <th class="eln-th">合计</th>
              <th class="eln-th">占比</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in costRows" :key="r.name">
              <td class="eln-td">{{ r.name }}</td>
              <td class="eln-td">¥ {{ r.mat }}</td>
              <td class="eln-td">¥ {{ r.svc }}</td>
              <td class="eln-td">¥ {{ r.total }}</td>
              <td class="eln-td">{{ r.pct }}</td>
            </tr>
            <tr>
              <td class="eln-td rp-total">合计 4 个项目</td>
              <td class="eln-td rp-total">¥ 30,840</td>
              <td class="eln-td rp-total">¥ 13,800</td>
              <td class="eln-td rp-total rp-blue">¥ 44,640</td>
              <td class="eln-td rp-total">100%</td>
            </tr>
          </tbody>
        </table>
        <div class="rp-footnote">
          项目花费 = 材料花费 + 测试表征花费。材料花费取任务消耗 Ledger 行按 project_id 分组 SUM(amount × 快照单价)（§7.21）；
          测试表征花费取「验收通过」的服务行（§7.23）；设备模板创建的库存不计入（SCN-RES-COST-6）。
          导出 Excel / PDF 与筛选条件一致（SCN-REPORT-2）。
        </div>
      </div>
    </div>

    <!-- ===== 面板 2：AI Token 消耗（云版） ===== -->
    <div v-else-if="activeTab === 'token'" class="rp-panel">
      <div class="rp-hint">
        云版专有报表 · 云版每次 AI 调用消耗 Token 并记录日志（SCN-AI-4）；私有化本地推理不消耗 Token，本报表显示空态（SCN-AI-5）。
        云版受账户余额限制（SCN-AI-6 / DEC-005），余额不足时调用前拦截并提示。
      </div>
      <div class="rp-card eln-card">
        <div class="rp-card-head">
          <div class="rp-card-title">AI Token 消耗报表</div>
          <div class="rp-card-note">按成员汇总 · 当前部署形态：云版 · 账户余额 128.4 万 Tokens</div>
        </div>
        <table class="eln-table">
          <thead>
            <tr>
              <th class="eln-th">成员</th>
              <th class="eln-th">调用次数</th>
              <th class="eln-th">Prompt Tokens</th>
              <th class="eln-th">Completion Tokens</th>
              <th class="eln-th">合计 Tokens</th>
              <th class="eln-th">估算费用（¥）</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in tokenRows" :key="r.name">
              <td class="eln-td">{{ r.name }}</td>
              <td class="eln-td">{{ r.calls }}</td>
              <td class="eln-td">{{ r.prompt }}</td>
              <td class="eln-td">{{ r.completion }}</td>
              <td class="eln-td">{{ r.total }}</td>
              <td class="eln-td">{{ r.fee }}</td>
            </tr>
            <tr>
              <td class="eln-td rp-total">合计 4 名成员</td>
              <td class="eln-td rp-total">400</td>
              <td class="eln-td rp-total">1,176,000</td>
              <td class="eln-td rp-total">266,000</td>
              <td class="eln-td rp-total rp-blue">1,442,000</td>
              <td class="eln-td rp-total rp-blue">119.00</td>
            </tr>
          </tbody>
        </table>
        <div class="rp-footnote">
          Token 消耗记录由 ai_eln 引擎的会话追踪 / 审计面板产出（ADR-0002 · D-persist=B）；
          估算费用按云版计费单价折算，仅作参考。私有化部署下本报表整体显示「本地推理不消耗 Token」空态。
        </div>
      </div>
    </div>

    <!-- ===== 面板 3：项目指标完成统计 ===== -->
    <div v-else-if="activeTab === 'kpi'" class="rp-panel">
      <div class="rp-card eln-card">
        <div class="rp-card-head">
          <div class="rp-card-title">项目指标完成统计</div>
          <div class="rp-card-note">指标来源：项目指标 Tab 的任务书解析（AI 提取后可人工修正） · 达成率 = 当前值 / 目标值</div>
        </div>
        <table class="eln-table">
          <thead>
            <tr>
              <th class="eln-th">项目</th>
              <th class="eln-th">指标项</th>
              <th class="eln-th">目标值</th>
              <th class="eln-th">当前值</th>
              <th class="eln-th">达成率</th>
              <th class="eln-th">状态</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in kpiRows" :key="i">
              <td class="eln-td">{{ r.proj }}</td>
              <td class="eln-td">{{ r.item }}</td>
              <td class="eln-td">{{ r.target }}</td>
              <td class="eln-td">{{ r.current }}</td>
              <td class="eln-td" :style="{ color: r.rateColor }">{{ r.rate }}</td>
              <td class="eln-td">
                <span class="status-dot" :style="{ background: kpiStatus[r.status].dot }"></span>
                <span :style="{ color: kpiStatus[r.status].fg }">{{ kpiStatus[r.status].label }}</span>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="rp-footnote">
          共 5 项指标 · 指标由项目指标 Tab 的任务书解析（AI）提取，可人工校正后作为统计基准（REQ-AI / §7.10）；
          状态枚举：已达成 / 进行中 / 未达成。导出 Excel / PDF 保留当前筛选条件与维度。
        </div>
      </div>
    </div>

    <!-- ===== 面板 4：实验设计迭代统计 ===== -->
    <div v-else class="rp-panel">
      <div class="rp-card eln-card">
        <div class="rp-card-head">
          <div class="rp-card-title">实验设计迭代统计</div>
          <div class="rp-card-note">统计口径：实验详情左栏「实验设计与配方优化」下的 DOE 轮次（混料设计 / RSM / 贝叶斯优化）</div>
        </div>
        <table class="eln-table">
          <thead>
            <tr>
              <th class="eln-th">项目</th>
              <th class="eln-th">实验数</th>
              <th class="eln-th">DOE 迭代轮次</th>
              <th class="eln-th">方案数</th>
              <th class="eln-th">采用方案</th>
              <th class="eln-th">最近迭代时间</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in doeRows" :key="r.proj">
              <td class="eln-td">{{ r.proj }}</td>
              <td class="eln-td">{{ r.exps }}</td>
              <td class="eln-td">{{ r.rounds }}</td>
              <td class="eln-td">{{ r.plans }}</td>
              <td class="eln-td" :class="{ 'rp-muted': r.pending }">{{ r.plan }}</td>
              <td class="eln-td">{{ r.date }}</td>
            </tr>
          </tbody>
        </table>
        <div class="rp-footnote">
          共 3 个项目 · 迭代轮次统计实验详情左栏「实验设计与配方优化」下已落地的 DOE 轮次（V1.22 / DEC-009 下放实验级）；
          「采用方案」标注最终采纳的那一版配方。四类报表均支持按当前筛选条件导出 Excel / PDF（SCN-REPORT-2）。
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'

const filters = [
  { label: 'range', value: '近 30 天' },
  { label: 'project', value: '全部项目' },
  { label: 'group', value: '全部小组' }
]

const tabs = [
  { key: 'cost', label: '项目花费报表' },
  { key: 'token', label: 'AI Token 消耗（云版）' },
  { key: 'kpi', label: '项目指标完成统计' },
  { key: 'doe', label: '实验设计迭代统计' }
]
const activeTab = ref('cost')

/* 面板 1：项目花费（画布 79:1264：4 项目，含高温硅胶研究 ¥ 16,000，总 ¥ 44,640） */
const costStats = [
  { label: '项目总花费（近 30 天）', value: '¥ 44,640' },
  { label: '材料花费（任务消耗出库）', value: '¥ 30,840' },
  { label: '测试表征花费（验收通过后计入）', value: '¥ 13,800' },
  { label: '覆盖项目 / 小组', value: '4 个 / 3 组' }
]
const dims = ['按项目', '按小组', '按时间']
const costDim = ref('按项目')
const costRows = [
  { name: '高温硅胶研究', mat: '12,400', svc: '3,600', total: '16,000', pct: '35.8%' },
  { name: 'PP 配方优化（主）', mat: '9,180', svc: '6,200', total: '15,380', pct: '34.5%' },
  { name: '阻燃 PP 开发', mat: '5,260', svc: '2,400', total: '7,660', pct: '17.2%' },
  { name: '高抗冲 PP 改性', mat: '4,000', svc: '1,600', total: '5,600', pct: '12.5%' }
]

/* 面板 2：AI Token */
const tokenRows = [
  { name: '张伟 · 项目负责人', calls: 128, prompt: '420,000', completion: '96,000', total: '516,000', fee: '42.80' },
  { name: '李娜 · 小组组长', calls: 96, prompt: '288,000', completion: '64,000', total: '352,000', fee: '29.10' },
  { name: '王强 · 组员', calls: 152, prompt: '396,000', completion: '88,000', total: '484,000', fee: '39.60' },
  { name: '邢海平 · 单位管理员', calls: 24, prompt: '72,000', completion: '18,000', total: '90,000', fee: '7.50' }
]

/* 面板 3：项目指标 */
/* 状态色取画布 79:1383/1384/1391/1399/1407/1415/1416 实测值（成功色为 #5EC66F） */
const kpiStatus = {
  done: { label: '已达成', dot: '#5EC66F', fg: '#5EC66F' },
  doing: { label: '进行中', dot: '#2563EB', fg: '#2563EB' },
  miss: { label: '未达成', dot: '#DF3562', fg: '#DF3562' }
}
const kpiRows = [
  { proj: 'PP 配方优化', item: '悬臂梁冲击强度', target: '≥ 45 kJ/m²', current: '52 kJ/m²', rate: '115.6%', rateColor: '#5EC66F', status: 'done' },
  { proj: 'PP 配方优化', item: '拉伸强度', target: '≥ 24 MPa', current: '23.1 MPa', rate: '96.3%', rateColor: '#2563EB', status: 'doing' },
  { proj: 'PP 配方优化', item: '材料成本', target: '≤ ¥12.0/kg', current: '¥11.4/kg', rate: '105.3%', rateColor: '#5EC66F', status: 'done' },
  { proj: '阻燃 PP 开发', item: 'UL94 阻燃等级', target: 'V-0', current: 'V-0', rate: '100%', rateColor: '#5EC66F', status: 'done' },
  { proj: '阻燃 PP 开发', item: '断裂伸长率', target: '≥ 120%', current: '96%', rate: '80.0%', rateColor: '#DF3562', status: 'miss' }
]

/* 面板 4：实验设计迭代 */
const doeRows = [
  { proj: 'PP 配方优化', exps: 8, rounds: '4 轮', plans: 26, plan: 'R4-配比 C（滑石粉 20% + POE 12%）', date: '2026-09-24', pending: false },
  { proj: '阻燃 PP 开发', exps: 5, rounds: '2 轮', plans: 11, plan: 'R2-方案 A（APP 18%）', date: '2026-09-20', pending: false },
  { proj: '高抗冲 PP 改性', exps: 3, rounds: '1 轮', plans: 6, plan: 'R1-基准配比（待迭代）', date: '2026-09-15', pending: true }
]
</script>

<style scoped>
.report-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:1217 内容区 gap 16 */
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
.rp-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.rp-head-note {
  max-width: 380px;
  font-size: 12px;
  color: var(--color-placeholder);
  text-align: right;
  line-height: 1.6;
  padding-top: 4px;
}

/* 工具栏（画布 79:1226：固定高 52，左组 gap10 / 右组 gap8） */
.rp-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  height: 52px;
}
.rp-filters {
  display: flex;
  gap: 10px;
}
.rp-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  color: var(--color-text-menu);
  transition: background 0.15s ease;
}
.rp-chip:hover {
  background: #F9FAFB;
}
.rp-caret {
  font-size: 13px;
  color: inherit;
}
.rp-export {
  display: flex;
  gap: 8px;
}

/* 页签条 */
.rp-tabs {
  display: flex;
  gap: 4px;
  padding: 6px;
}
.rp-tab {
  height: 32px;
  padding: 0 16px;
  background: none;
  border: none;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-subtle-text);
  transition: background 0.15s ease, color 0.15s ease;
}
.rp-tab:hover {
  background: var(--color-fill-soft);
  color: var(--color-text);
}
.rp-tab.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}

/* 面板 */
.rp-panel {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
/* 云版专有提示条（画布 79:1312：通栏无圆角，底 #F5F3FF / 字 #6F2DC1 / pad 12·20） */
.rp-hint {
  background: #F5F3FF;
  color: #6F2DC1;
  font-size: 12px;
  line-height: 1.7;
  padding: 12px 20px;
}
.rp-stat-row {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
}
/* 统计卡（画布 79:1252：h76 / pad 14·18 / 标签12 #71717A / 数值24） */
.rp-stat {
  height: 76px;
  padding: 14px 18px;
}
.rp-stat-label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.rp-stat-value {
  margin-top: 6px;
  font-size: 24px;
  font-weight: 600;
  color: var(--color-text);
}

/* 表卡（画布 79:1264：卡片 padding=0 / r12 / 撑满内容宽；内缩下沉到卡头与表格单元格） */
.rp-card {
  padding: 0;
  overflow: hidden;
}
/* 卡头（画布 79:1265：h56 / padding 0 20 / gap 12 / 垂直居中） */
.rp-card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  height: 56px;
  padding: 0 20px;
}
.rp-card-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
  display: flex;
  align-items: baseline;
  gap: 10px;
  flex-wrap: wrap;
}
/* 口径说明 / 卡头副题（画布 79:1267 / 79:1316 / 79:1369 / 79:1422：11px #A1A1AA） */
.rp-card-sub,
.rp-card-note {
  font-size: 11px;
  font-weight: 400;
  color: var(--color-placeholder);
}
/* 维度分段控件（画布 79:1268 容器 h28 / 项 h24 pad 10 r6） */
.rp-dim {
  display: flex;
  gap: 2px;
  background: var(--color-fill-soft);
  border-radius: var(--radius-button);
  padding: 2px;
  flex-shrink: 0;
}
.rp-dim-btn {
  height: 24px;
  padding: 0 10px;
  background: none;
  border: none;
  border-radius: var(--radius-small);
  font-size: 12px;
  color: var(--color-text-secondary);
}
.rp-dim-btn.active {
  background: var(--color-card);
  color: var(--color-primary);
  font-weight: 500;
  box-shadow: var(--shadow-card);
}
.rp-blue {
  color: var(--color-primary);
  font-weight: 600;
}
.rp-muted {
  color: var(--color-placeholder);
}

/* 本页表格（画布 79:1275 / 1282 / 1303）：表头 40 / 数据行 46（+1px 分隔线 = 47）/ 合计行 46+#FAFAFA。
   列内边距走全局画布栅格（tokens.css .eln-th/.eln-td），卡片已 padding:0。 */
.report-page .eln-td {
  height: 46px;
  border-bottom: 1px solid var(--color-border);
}
.report-page .eln-td.rp-total {
  height: 46px;
  border-top: none;
  border-bottom: none;
  background: var(--color-page-bg);
  font-weight: 500;
}
/* 表尾提示（画布 79:1309：h58 / padding 12px 20px 14px；11px #A1A1AA，无底色） */
.rp-footnote {
  padding: 12px 20px 14px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
}
</style>
