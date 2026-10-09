<template>
  <!-- 资源申请详情（画布 79:812 / PRD §7.9.3 · REQ-RES-APPROVE 二段式审批） -->
  <!-- notFound / forbidden 两个兜底分支（service 端真实存在时返回的真值） -->
  <div v-if="applyDetailPayload.notFound" class="ra-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">申请不存在</span>
    </div>
    <p class="ra-meta">申请单 {{ no }} 不存在或已删除。</p>
  </div>
  <div v-else-if="applyDetailPayload.forbidden" class="ra-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">无权访问</span>
    </div>
    <p class="ra-meta">您没有权限查看该申请单。</p>
  </div>
  <div v-else class="ra-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源中心</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/eln_res_center" class="crumb-link">资源申请</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">{{ app.no }}</span>
    </div>

    <!-- 页头 -->
    <div class="ra-head">
      <div class="ra-head-left">
        <!-- 导航器开关（画布 79:818） -->
        <button
          class="eln-icon-btn"
          title="导航器"
          @click="ui.navigatorOpen ? closeNavigator() : openNavigator()"
        >
          <AppIcon name="navigator" :size="16" />
        </button>
        <div class="ra-titles">
          <div class="ra-title-row">
            <h1 class="ra-title">{{ app.no }}</h1>
            <span class="ra-badge">{{ app.statusLabel }}</span>
          </div>
          <p class="ra-meta">
            {{ firstItemKindLabel }} · {{ firstItemName }} ·
            提交于 {{ app.submittedAt || '—' }} · 提交人 {{ requestorName }}
          </p>
        </div>
      </div>
      <router-link to="/eln_res_center" class="ra-back">← 返回申请列表</router-link>
    </div>

    <!-- 操作条（OPEN-10 写流程：按钮显隐由真库权限位驱动，REQ-RES-APPROVE 二段式） -->
    <div v-if="actions.length" class="ra-card ra-actions">
      <div class="ra-actions-info">
        <span class="ra-actions-label">{{ actionsLabel }}</span>
        <span class="ra-actions-note">操作即落库并刷新本页；驳回原因写入审批流转记录（SCN-RES-APPROVE-1/2）</span>
      </div>
      <div class="ra-actions-btns">
        <button
          v-for="a in actions"
          :key="a.type"
          class="ra-act-btn"
          :class="[a.tone, { busy }]"
          :disabled="busy"
          @click="run(a)"
        >{{ a.label }}</button>
      </div>
    </div>

    <!-- 到货验收（REQ-RES-RECEIPT / ADR-0032）：照片 + 本批数量 + 分批进度 + 逐轮记录 -->
    <div v-if="isMaterial && receiptStageVisible" class="ra-card ra-receipt">
      <div class="ra-card-head">
        <h3 class="ra-card-title">到货验收</h3>
        <span class="ra-card-note">
          已验 {{ receiptProgress.verifiedQty }} / 共 {{ receiptProgress.appliedQty }}{{ unitLabel }}
          —— 照片是入库的前置证据，累计达量才收口（SCN-RES-RECEIPT-1/3）
        </span>
      </div>

      <!-- 申请人：提交本批验收 -->
      <div v-if="approvals.canSubmitReceipt" class="ra-receipt-form">
        <label class="ra-field">
          <span class="ra-field-label">本批到货数量 *（{{ unitLabel }}）</span>
          <input v-model="receiptQty" type="number" min="0" step="0.01" class="ra-receipt-input" placeholder="例如 4" />
        </label>
        <label class="ra-field">
          <span class="ra-field-label">到货照片 *（至少一张）</span>
          <input type="file" accept="image/*" multiple class="ra-receipt-input" @change="onReceiptFiles" />
        </label>
        <div class="ra-receipt-actions">
          <button class="ra-act-btn primary" :class="{ busy }" :disabled="busy" @click="submitReceipt">
            提交本批验收
          </button>
          <span class="ra-actions-note">提交后由验货人判定；判不通过需退回重走审批</span>
        </div>
      </div>

      <!-- 逐轮验收记录（分批可见，照片留档） -->
      <div v-if="receiptProgress.rounds.length" class="ra-receipt-rounds">
        <div v-for="r in receiptProgress.rounds" :key="r.id" class="ra-receipt-round">
          <div class="ra-receipt-round-head">
            <span class="ra-receipt-chip" :class="r.status === 'passed' ? 'ok' : (r.status === 'rejected' ? 'bad' : 'wait')">
              {{ r.statusLabel }}
            </span>
            <span class="ra-receipt-round-qty">{{ r.qty }} {{ unitLabel }}</span>
            <span v-if="r.verifier" class="ra-muted">验货人：{{ r.verifier }}</span>
            <span v-if="r.verifiedAt" class="ra-muted">{{ r.verifiedAt }}</span>
          </div>
          <div v-if="r.rejectionReason" class="ra-receipt-round-reason">不通过理由：{{ r.rejectionReason }}</div>
          <div v-if="r.photos.length" class="ra-receipt-round-photos">
            <span v-for="p in r.photos" :key="p.id" class="ra-receipt-photo-chip">{{ p.filename }}</span>
          </div>
        </div>
      </div>
      <p v-else class="ra-footnote">尚无验收记录</p>
    </div>

    <div class="ra-main">
      <div class="ra-card ra-info">
        <div class="ra-card-head">
          <h3 class="ra-card-title">申请信息</h3>
          <span class="ra-card-note">状态枚举固定：待审批 / 已通过 / 驳回 / 已完成（SCN-RES-APPLY-2）</span>
        </div>
        <div class="ra-fields">
          <div class="ra-field-row">
            <div class="ra-field">
              <span class="ra-field-label">申请编号</span>
              <span class="ra-field-value strong">{{ app.no }}</span>
            </div>
            <div class="ra-field">
              <span class="ra-field-label">资源类型</span>
              <span class="ra-field-value strong">{{ firstItemKindLabel }} · {{ firstItemName }}</span>
            </div>
          </div>
          <div class="ra-divider"></div>
          <div class="ra-field-row">
            <div class="ra-field">
              <span class="ra-field-label">申请项目</span>
              <span class="ra-field-value strong blue">{{ app.project ? app.project.name : '—' }}</span>
            </div>
            <div class="ra-field">
              <span class="ra-field-label">数量（审批表单次数）</span>
              <span class="ra-field-value strong">{{ firstItemQty }}</span>
            </div>
          </div>
          <div class="ra-divider"></div>
          <div class="ra-field-row">
            <div class="ra-field">
              <span class="ra-field-label">单价（服务档案快照）</span>
              <span class="ra-field-value">{{ firstItemUnitPrice }}</span>
            </div>
            <div class="ra-field">
              <span class="ra-field-label">预计金额</span>
              <span class="ra-field-value strong">{{ firstItemAmount }}</span>
            </div>
          </div>
          <!-- 材料类 = 请购单（ADR-0030 / SQ-2026-7783）：申请时选定「目标库」，
               终审通过后由终审人点「到货验收入库」写进该库；入库后落库条目再被关联任务消耗。
               未指定目标库则只显示「未指定」，不编占位文案。 -->
          <template v-if="isMaterial">
            <div class="ra-divider"></div>
            <div class="ra-field-row">
              <div class="ra-field">
                <span class="ra-field-label">目标库（请购入库库位）</span>
                <span v-if="targetRepositoryName" class="ra-field-value strong">{{ targetRepositoryName }}</span>
                <span v-else class="ra-field-value ra-muted">未指定目标库</span>
              </div>
              <div class="ra-field">
                <span class="ra-field-label">入库后落库条目</span>
                <span v-if="receivedRowLabel" class="ra-field-value strong">{{ receivedRowLabel }}</span>
                <span v-else class="ra-field-value ra-muted">尚未入库（点「到货验收入库」后生成）</span>
              </div>
            </div>
            <div class="ra-divider"></div>
            <div class="ra-field-row">
              <div class="ra-field">
                <span class="ra-field-label">关联任务（预计消耗任务）</span>
                <span v-if="app.myModule" class="ra-field-value strong">{{ app.myModule.name }}</span>
                <span v-else class="ra-field-value ra-muted">未关联（无任务消耗则不出库）</span>
              </div>
            </div>
          </template>
          <div class="ra-divider"></div>
          <div class="ra-field-row">
            <div class="ra-field">
              <span class="ra-field-label">提交人</span>
              <span class="ra-field-value strong">{{ requestorName }}</span>
            </div>
            <div class="ra-field">
              <span class="ra-field-label">提交时间</span>
              <span class="ra-field-value">{{ app.submittedAt || '—' }}</span>
            </div>
          </div>
          <div class="ra-divider"></div>
          <div class="ra-field-full">
            <span class="ra-field-label">同时解除位置指派</span>
            <span class="ra-field-value">
              否（默认不勾选；仅整件领用／报废场景由用户显式勾选，DEC-017 / 待确认 F）
            </span>
          </div>
          <div class="ra-divider"></div>
          <div class="ra-field-full">
            <span class="ra-field-label">申请说明</span>
            <span class="ra-field-value">
              {{ app.note && app.note.length > 0 ? app.note : '（无说明）' }}
            </span>
          </div>
        </div>
      </div>

      <div class="ra-card ra-flow">
        <div class="ra-card-head">
          <h3 class="ra-card-title">审批流转记录</h3>
        </div>
        <div class="ra-timeline">
          <div v-for="n in timelineNodes" :key="n.step" class="ra-node">
            <div class="ra-node-mark">
              <span class="ra-dot" :class="n.tone"></span>
            </div>
            <div class="ra-node-body">
              <div class="ra-node-step">{{ n.step }}</div>
              <div class="ra-node-meta">{{ n.meta }}</div>
              <div class="ra-node-note">{{ n.note }}</div>
            </div>
          </div>
        </div>
        <div class="ra-flow-foot">
          未审批通过不计入项目花费（SCN-RES-APPROVE-5）；审批流转记录对提交人可见（SCN-RES-APPLY-3）。
          二段式审批引用 REQ-RES-APPLY / REQ-RES-APPROVE，不另造审批流。
        </div>
      </div>
    </div>

    <!-- 出库 / 执行登记 / 结果回填（材料类与测试表征类两套口径，SCN-RES-APPROVE-3/4） -->
    <div class="ra-card">
      <div class="ra-card-head">
        <h3 class="ra-card-title">{{ isMaterial ? '到货验收 / 入库登记' : '执行登记 / 结果回填' }}</h3>
        <span class="ra-card-note">
          <template v-if="isMaterial">
            材料类终审通过后**不自动入库**：须由终审人在本页点「到货验收入库」，系统才把料写进目标库
            （建/累加条目与库存值）。出库仍由所关联任务的原生「实验消耗」触发（任务消耗 → 写
            RepositoryLedgerRecord → 同步消耗明细并扣减库存）。
          </template>
          <template v-else>
            测试表征类终审通过＝获得执行许可（不建库存、不入额度，V1.21）；执行完成后在「消耗 / 执行明细表」登记服务行，
            按服务档案验收闸门决定何时计入花费（SCN-RES-APPROVE-4 · REQ-RES-TEST · REQ-RES-CONSUME）。
          </template>
        </span>
      </div>
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th" style="width:190px">环节</th>
            <th class="eln-th" style="width:100px">状态</th>
            <th class="eln-th" style="width:150px">时间</th>
            <th class="eln-th" style="width:90px">操作人</th>
            <th class="eln-th">备注</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in stages" :key="s.stage">
            <td class="eln-td ra-strong">{{ s.stage }}</td>
            <td class="eln-td ra-strong" :class="s.tone">{{ s.state }}</td>
            <td class="eln-td" :class="{ 'ra-muted': s.time === '—' }">{{ s.time }}</td>
            <td class="eln-td">{{ s.user }}</td>
            <td class="eln-td" :class="s.noteTone || 'ra-secondary'">{{ s.note }}</td>
          </tr>
        </tbody>
      </table>
      <div class="ra-card-foot">
        <template v-if="isMaterial">
          材料入库走原生库存链路（ADR-0030）：批不批都不写库，只有点「到货验收入库」才写。
          下表为该单入库后的实际条目上的任务消耗流水（出库）。
        </template>
        <template v-else>
          本单全程不产生库存 / Ledger 行（V1.21）；服务行三态由验收闸门决定是否计入花费——待验收（不计花费） → 待回填（已计入） → 已归档。
          未审批通过不计入项目花费（SCN-RES-APPROVE-5）。
        </template>
      </div>
    </div>

    <!-- 关联出入库 / 消耗记录（材料类专属）：绑定库存条目 → 任务消耗流水反查 -->
    <div v-if="isMaterial" class="ra-card">
      <div class="ra-card-head">
        <h3 class="ra-card-title">关联出入库 / 消耗记录</h3>
        <span class="ra-card-note">
          按本单入库后的实际条目反查原生任务消耗流水（reference_type = MyModuleRepositoryRow 同步来的消耗明细）。
        </span>
      </div>
      <table class="eln-table">
        <thead>
          <tr>
            <th class="eln-th" style="width:150px">时间</th>
            <th class="eln-th">名称</th>
            <th class="eln-th" style="width:110px">数量</th>
            <th class="eln-th" style="width:120px">金额</th>
            <th class="eln-th" style="width:100px">结果状态</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in linkedConsumptions" :key="c.id">
            <td class="eln-td">{{ c.occurredAt }}</td>
            <td class="eln-td ra-strong">{{ c.name }}</td>
            <td class="eln-td">{{ c.qty }}</td>
            <td class="eln-td ra-strong ra-purple">{{ c.amount }}</td>
            <td class="eln-td" :class="{ 'ra-muted': c.resultStatus === '—' || !c.resultStatus }">
              {{ c.resultStatus || '—' }}
            </td>
          </tr>
          <tr v-if="!linkedConsumptions.length">
            <td class="eln-td ra-muted" colspan="5">
              {{ receivedRowLabel ? '该库存条目上还没有任务消耗流水 —— 出库尚未发生（去「关联任务」里登记消耗后即出现）。'
                              : '本单尚未入库，因此不会有任何出入库/消耗记录。' }}
            </td>
          </tr>
        </tbody>
      </table>
      <div class="ra-card-foot">
        共 {{ linkedConsumptions.length }} 条 · 出库＝任务消耗（负向扣减库存）；只读反查，不在本页写库。
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'
import { isEmbedded } from '../utils/env'
import { applyDetailPayload } from '../data/mock'

// 申请号：两种模式**同一串路径** `/eln_res_apply/:no`，区别只在载体 ——
//   内嵌态在 pathname（整页 URL）；SPA 态在 hash（createWebHashHistory）。
//   模式判定走 env.js 的显式标记，不再靠「试两个正则看哪个能匹配上」。
// ⚠ 旧实现在 SPA 态匹配的是 `/apply-detail/` 这个**早已不存在的路由段**，
//   所以 SPA 态恒取不到 no —— 影响 notFound 分支文案与操作条的提交地址。
//   这是旧「两套路径词汇表」被静默掩盖的残留，随本轮统一一并修掉。
const APPLY_NO_RE = /eln_res_apply\/([^/?#]+)/
const no = ((isEmbedded() ? location.pathname : location.hash).match(APPLY_NO_RE) || [])[1] || ''

const app = applyDetailPayload.application
const items = applyDetailPayload.items
const meta = applyDetailPayload.meta || {}
const approvals = applyDetailPayload.approvals || {}
// 入库后落库条目 → 任务消耗流水（材料类才有；服务类恒为空数组）
const linkedConsumptions = applyDetailPayload.linkedConsumptions || []
const firstItem = items[0] || {}
const firstItemName = firstItem.name || '—'
const firstItemKindLabel = firstItem.kindLabel || '材料'
// 材料 / 服务两套口径（SCN-RES-APPROVE-3 vs -4）：页面文案与阶段表都要跟着切
const isMaterial = (firstItem.kind || 'material') === 'material'
// 请购语义（ADR-0030）：目标库（申请时选定）+ 入库后落库条目（验收时写回）
const targetRepositoryName = firstItem.targetRepositoryName || ''
const receivedRowLabel = firstItem.receivedRepositoryRowName || ''
const firstItemQty = firstItem.qty || '—'
const firstItemUnitPrice = firstItem.unitPrice || '—'
const firstItemAmount = firstItem.amount || '—'
const requestorName = app.requestor ? app.requestor.name : '—'

// 时间轴派生自 applyDetailPayload.timeline（service 端真值：created/submitted/group/project/completed/rejected）
const timelineNodes = applyDetailPayload.timeline.map(e => ({
  step: e.label,
  meta: e.at ? `${e.at}${e.by ? ' · ' + e.by.name : ''}` : '—',
  note: noteFor(e.key),
  tone: toneFor(e.key)
}))

function noteFor(key) {
  return {
    created:   '创建申请',
    submitted: '提交审批',
    group:     '小组组长初审通过（SCN-RES-APPROVE-1）',
    project:   '项目负责人终审通过（SCN-RES-APPROVE-2）',
    completed: isMaterial ? '已验收入库 · 库存已写入目标库' : '执行完成 · 服务行已登记',
    rejected:  '已驳回'
  }[key] || ''
}

function toneFor(key) {
  if (key === 'completed') return 'green'
  return 'blue'
}

// ---- OPEN-10 写流程：动作条（权限位与后端 Workflow 同口径） ----
const busy = ref(false)
const actions = []
if (meta.canSubmit) actions.push({ type: 'submit', label: '提交审批', tone: 'primary' })
if (approvals.canApproveGroup) {
  actions.push({ type: 'approve_group', label: '初审通过', tone: 'primary' })
  actions.push({ type: 'reject', label: '驳回', tone: 'danger' })
}
if (approvals.canApproveProject) {
  actions.push({ type: 'approve_project', label: '终审通过', tone: 'primary' })
  actions.push({ type: 'reject', label: '驳回', tone: 'danger' })
}
// ⚠ ADR-0032：材料类的终态动作是「验货通过」，权限位换成 approvals.canVerifyReceipt
//   （后端把材料类从 available_actions 里摘掉了 complete —— 否则会给终审人显示一个
//   「点了必被拒」的按钮）。这里**不能**再用 meta.canComplete。
if (approvals.canVerifyReceipt) {
  actions.push({ type: 'complete', label: '验货通过并入库', tone: 'primary' })
  if (approvals.canRejectReceipt) actions.push({ type: 'reject_receipt', label: '验货不通过', tone: 'danger' })
}

const actionsLabel = meta.canSubmit ? '您是申请人，可将本单提交进入二段式审批（SCN-RES-APPLY-1）' :
  approvals.canApproveGroup ? '初审：通过后转项目负责人终审（SCN-RES-APPROVE-1）' :
  approvals.canApproveProject ? (isMaterial ? '终审：通过后由申请人交到货照片，再由验货人判定入库（ADR-0032）' : '终审：通过后测试表征获得执行许可（SCN-RES-APPROVE-2/4）') :
  approvals.canSubmitReceipt ? '请在下方「到货验收」上传本批到货照片与数量' :
  approvals.canVerifyReceipt ? '请验货：核对照片与本批数量后判定通过或退回' :
  '等待申请人提交到货照片，或由验货人判定（SCN-RES-RECEIPT）'

async function run(a) {
  if (busy.value) return
  let reason = null
  if (a.type === 'reject') {
    reason = window.prompt('驳回原因（写入审批流转记录）：')
    if (reason === null) return // 用户取消
  }
  // ⚠ 验货不通过：理由**必填**（SCN-RES-RECEIPT / ADR-0032 D4）——
  //   申请人要靠它知道该补什么货，空理由等于把球踢回去。
  if (a.type === 'reject_receipt') {
    reason = window.prompt('验货不通过理由（必填，申请人据此补货）：')
    if (reason === null) return
    if (!String(reason).trim()) { window.alert('理由不能为空：申请人要靠它补货'); return }
  }
  busy.value = true
  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')
    const res = await fetch(`/eln_res_apply/${encodeURIComponent(no)}/actions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(csrf ? { 'X-CSRF-Token': csrf.content } : {})
      },
      body: JSON.stringify({ type: a.type, reason })
    })
    const data = await res.json()
    if (data.ok) {
      window.location.reload() // 详情页整页重取 payload（真值渲染时间线/状态）
    } else {
      window.alert('操作失败：' + (data.error || '未知错误'))
    }
  } catch {
    window.alert('操作失败：网络错误或登录态失效')
  } finally {
    busy.value = false
  }
}

// 到货验收 / 入库登记 —— 材料类与测试表征类**两套口径**（ADR-0030 / SQ-2026-7783 修复）
//   材料：入库**不**在审批事件上自动发生，须点「到货验收入库」才写进目标库（建/累加条目与库存值）；
//         出库则仍由关联任务的原生「实验消耗」触发。所以是「授权 → 到货入库 → 任务消耗出库」三段。
//   服务：终审通过＝获得执行许可，不建库存、不入额度（SCN-RES-APPROVE-4）。
// 状态文案一律由真值派生（status / projectApprovedAt / linkedConsumptions），不写死演示值。
const latestConsumption = linkedConsumptions[0] || null // payload 按 occurred_at 倒序

// ---- 到货验收（REQ-RES-RECEIPT / ADR-0032）----
// ⚠ payload 里的 receiptProgress 在**旧 payload**（独立 SPA 跑 mock）里可能不存在，
//   所以这里给一份同形空对象而不是直接解构 —— 否则老 mock 会把整页打崩。
const receiptProgress = applyDetailPayload.receiptProgress || { appliedQty: '0', verifiedQty: '0', rounds: [] }
const receiptQty = ref('')
const receiptFiles = ref([])
// 单位取申请单申报的那个（payload 的 item 是 camelCase 化的，字段名跟着邻居走）
const unitLabel = firstItem.unit || ''

// 只在「材料类 + 已经过终审或已收口」时显示验收卡：
// 还没终审的单子挂一个空验收区纯属噪声（那时还没有「到货」这回事）。
// ⚠ isMaterial 是**普通布尔**不是 ref（见上方声明），这里不能写 isMaterial.value。
const receiptStageVisible = computed(() =>
  isMaterial && ['project_approved', 'completed'].includes(app.status))

function onReceiptFiles(e) {
  receiptFiles.value = Array.from((e && e.target && e.target.files) || [])
}

// 提交本批验收：走 **multipart FormData**（照片是文件，不能 JSON 化）
async function submitReceipt() {
  if (busy.value) return
  const qty = Number(receiptQty.value)
  if (!Number.isFinite(qty) || qty <= 0) { window.alert('请填写本批到货数量（必须大于 0）'); return }
  if (!receiptFiles.value.length) { window.alert('请至少上传一张到货照片（照片是入库的前置证据）'); return }

  const fd = new FormData()
  fd.append('type', 'submit_receipt')
  fd.append('receipt_qty', String(qty))
  receiptFiles.value.forEach((f) => fd.append('receipt_photos[]', f))

  busy.value = true
  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')
    // ⚠ FormData 不能手动设 Content-Type —— 浏览器要自己带 multipart boundary
    const res = await fetch(`/eln_res_apply/${encodeURIComponent(no)}/actions`, {
      method: 'POST',
      headers: csrf ? { 'X-CSRF-Token': csrf.content } : {},
      body: fd
    })
    const data = await res.json().catch(() => ({}))
    if (data.ok) window.location.reload()
    else window.alert('提交失败：' + (data.error || '未知错误'))
  } catch {
    window.alert('提交失败：网络错误或登录态失效')
  } finally {
    busy.value = false
  }
}

function approvalStateLabel(status) {
  return {
    draft: '待提交',
    submitted: '待终审',
    group_approved: '待终审',
    project_approved: '已授权',
    completed: '已授权',
    rejected: '未授权'
  }[status] || '—'
}

function approvalStateTone(status) {
  if (status === 'project_approved' || status === 'completed') return 'ra-green'
  if (status === 'rejected') return 'ra-red'
  return 'ra-orange'
}

const materialStages = [
  {
    stage: '终审通过 → 解锁到货验收',
    state: approvalStateLabel(app.status),
    tone: approvalStateTone(app.status),
    time: app.projectApprovedAt || '—',
    user: app.projectReviewer ? app.projectReviewer.name : '—',
    note: '材料类终审通过只解锁入库，不直接写库（ADR-0030）'
  },
  {
    stage: '到货验收入库（写入目标库）',
    state: app.status === 'completed' ? '已入库' : '待入库',
    tone: app.status === 'completed' ? 'ra-green' : 'ra-orange',
    time: app.completedAt || '—',
    user: '—',
    note: targetRepositoryName ? `目标库：${targetRepositoryName}` : '未指定目标库'
  },
  {
    stage: '任务实验消耗（出库触发点）',
    state: linkedConsumptions.length ? `已发生 ${linkedConsumptions.length} 笔` : '尚未发生',
    tone: linkedConsumptions.length ? 'ra-green' : 'ra-muted',
    time: latestConsumption ? latestConsumption.occurredAt : '—',
    user: '—',
    note: app.myModule ? `关联任务：${app.myModule.name}` : '未关联任务 —— 无实验消耗则不出库',
    noteTone: app.myModule ? 'ra-purple' : 'ra-orange'
  }
]

const serviceStages = [
  {
    stage: '终审通过 → 执行许可',
    state: '已发放',
    tone: 'ra-blue',
    time: app.projectApprovedAt || '—',
    user: app.projectReviewer ? app.projectReviewer.name : '—',
    note: '测试表征类不建库存、不入额度（V1.21）'
  },
  {
    stage: '执行登记（消耗/执行明细表）',
    state: '已登记',
    tone: 'ra-green',
    time: app.completedAt || '—',
    user: app.requestor ? app.requestor.name : '—',
    note: `服务行 × ${firstItem.qtyRaw || 0} 次 · 单价快照 ${firstItem.unitPrice || '—'} · 合计 ${firstItem.amount || '—'}`,
    noteTone: 'ra-purple'
  },
  {
    stage: '结果回填（ResultAsset 挂执行单）',
    state: '待回填',
    tone: 'ra-orange',
    time: '—',
    user: app.requestor ? app.requestor.name : '—',
    note: '结果须以 ResultAsset 上传任务 Results 并显式挂载到执行单（V1.22 不变项）'
  }
]

const stages = isMaterial ? materialStages : serviceStages
</script>

<style scoped>
.ra-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:815 内容区 gap 16 */
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
.ra-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.ra-head-left {
  display: flex;
  align-items: center;
  gap: 16px; /* 画布 79:817 页头 gap 16 */
}
.ra-title-row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.ra-title {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.ra-badge {
  display: inline-flex;
  align-items: center;
  height: 24px;
  padding: 0 10px;
  border-radius: 6px;
  background: #EEF4FF;
  font-size: 12px;
  font-weight: 500;
  color: var(--color-primary);
}
.ra-meta {
  margin: 4px 0 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.ra-back {
  padding-top: 6px;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-primary);
  white-space: nowrap;
}

/* 操作条（OPEN-10 写流程） */
.ra-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 20px;
}
.ra-actions-info {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}
.ra-actions-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.ra-actions-note {
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-placeholder);
}
.ra-actions-btns {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}
.ra-act-btn {
  height: 32px;
  padding: 0 16px;
  border: none;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: filter 0.15s ease, opacity 0.15s ease;
}
.ra-act-btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
.ra-act-btn.primary {
  background: var(--color-primary);
  color: #fff;
}
.ra-act-btn.primary:hover:not(:disabled) {
  filter: brightness(1.08);
}
.ra-act-btn.danger {
  background: none;
  border: 1px solid #DF3562;
  color: #DF3562;
}
.ra-act-btn.danger:hover:not(:disabled) {
  background: rgba(223, 53, 98, 0.06);
}

/* 主区 */
.ra-main {
  display: flex;
  align-items: flex-start;
  gap: 16px;
}
.ra-card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.ra-info {
  flex: 1;
  min-width: 0;
}
.ra-flow {
  width: 400px;
  flex-shrink: 0;
}
.ra-card-head {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 14px 20px;
}
.ra-flow .ra-card-head {
  padding: 14px 18px;
}
.ra-card-title {
  margin: 0;
  font-size: 14px;
  font-weight: 500;
  color: var(--color-text);
  white-space: nowrap;
}
.ra-card-note {
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-placeholder);
}
.ra-card-foot {
  padding: 12px 20px 14px;
  font-size: 11px;
  line-height: 1.8;
  color: var(--color-placeholder);
}

/* 字段区 */
.ra-fields {
  padding: 6px 20px 16px;
}
.ra-field-row {
  display: flex;
  gap: 16px;
  padding: 10px 0;
}
.ra-field {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.ra-field-full {
  display: flex;
  flex-direction: column;
  gap: 3px;
  padding: 10px 0 4px;
}
.ra-field-label {
  font-size: 11px;
  color: var(--color-placeholder);
}
.ra-field-value {
  font-size: 13px;
  line-height: 1.6;
  color: var(--color-text);
}
.ra-field-value.strong {
  font-weight: 500;
}
.ra-field-value.blue {
  color: var(--color-primary);
}
.ra-divider {
  height: 1px;
  background: var(--color-table-header);
}

/* 时间轴 */
.ra-timeline {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 16px 18px;
}
.ra-node {
  display: flex;
  gap: 10px;
}
.ra-node-mark {
  padding-top: 5px;
}
.ra-dot {
  display: block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--color-primary);
}
.ra-dot.green {
  background: var(--status-done);
}
.ra-node-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.ra-node-step {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.ra-node-meta {
  font-size: 11px;
  color: var(--color-placeholder);
}
.ra-node-note {
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-subtle-text);
}
.ra-flow-foot {
  padding: 12px 18px 14px;
  border-top: 1px solid var(--color-table-header);
  font-size: 11px;
  line-height: 1.8;
  color: var(--color-placeholder);
}

/* 文本色 */
.ra-strong {
  font-weight: 500;
}
.ra-secondary {
  color: var(--color-subtle-text);
}
.ra-muted {
  color: var(--color-placeholder);
}
.ra-blue {
  color: var(--color-primary);
}
.ra-purple {
  color: #6F2DC1;
}
.ra-orange {
  color: #E9A845;
}
.ra-red {
  color: #DF3562;
}
.ra-green {
  color: var(--status-done);
}
/* ---- 到货验收（REQ-RES-RECEIPT / ADR-0032）---- */
.ra-receipt {
  margin-bottom: 12px;
}
.ra-receipt-form {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: 12px;
  padding: 10px 0 4px;
}
.ra-receipt-input {
  height: 30px;
  padding: 0 8px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 12px;
  color: var(--color-text);
  background: var(--color-card);
  box-sizing: border-box;
}
.ra-receipt-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}
.ra-receipt-rounds {
  margin-top: 8px;
  border-top: 1px solid var(--color-border);
  padding-top: 8px;
}
.ra-receipt-round {
  padding: 6px 0;
  border-bottom: 1px dashed var(--color-border);
}
.ra-receipt-round-head {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 12px;
}
.ra-receipt-chip {
  padding: 1px 8px;
  border-radius: 10px;
  font-size: 11px;
  font-weight: 500;
  border: 1px solid var(--color-border);
  color: var(--color-text-secondary);
}
.ra-receipt-chip.ok {
  color: var(--status-done);
  border-color: var(--status-done);
}
.ra-receipt-chip.bad {
  color: #DF3562;
  border-color: #DF3562;
}
.ra-receipt-chip.wait {
  color: var(--color-primary);
  border-color: var(--color-primary);
}
.ra-receipt-round-qty {
  font-weight: 500;
  color: var(--color-text);
}
.ra-receipt-round-reason {
  margin-top: 4px;
  font-size: 12px;
  color: #DF3562;
}
.ra-receipt-round-photos {
  margin-top: 4px;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.ra-receipt-photo-chip {
  font-size: 11px;
  padding: 1px 6px;
  border-radius: 4px;
  background: var(--color-bg, #F4F4F5);
  color: var(--color-text-secondary);
}
</style>

