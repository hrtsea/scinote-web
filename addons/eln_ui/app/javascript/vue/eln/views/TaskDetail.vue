<template>
  <!-- 任务详情（画布 4:71）：面包屑 + 页头 + 双栏（左主区 4:733 + 右属性区 330 6 卡） -->
  <!--
    ⚠ 2026-10-05 接真改造（不编造规矩）：原型这一页写死了 8 处演示文案，真机无一为真 ——
      底涂剂选型对比实验 / EX1 · 硅胶配方与固化体系筛选 / 待审核 / 李组员 / 王组长 /
      张负责人 / 假 500h 老化数据图 / 假 5 条流程轨迹。
      处理方式分三类，没有第四类（不许拿原型文案顶）：
        A. 原生有承载面 → 直接接真：所属实验、状态、指派人、Protocol 步骤、checklist、
           讨论评论、Result 成果、关联试剂、创建时间、流程轨迹。
        B. 原生没有、addon 有自有表 → 读 eln_ui_task_profiles：任务目的、执行计划、负责人。
        C. 原生没有也没有二开表 → **显式留白 + 说明为什么取不到**：
           完成申请时间、五态机「提交完成申请/待审核」两档、结论、关联项目指标。
  -->
  <div class="task-detail">
    <div class="breadcrumb">
      <template v-for="(c, i) in crumbs" :key="i">
        <span v-if="i > 0" class="crumb-sep">/</span>
        <router-link v-if="c.to" :to="c.to" class="crumb-link">{{ c.label }}</router-link>
        <span v-else class="crumb-current">{{ c.label }}</span>
      </template>
    </div>

    <!-- 页头 4:720（标题/徽标/操作组全走真值） -->
    <PageHeader
      :title="taskName"
      :subtitle="headerSubtitle"
    >
      <template #title-extra>
        <span class="eln-badge" :class="statusBadgeClass">{{ statusText }}</span>
        <span v-if="profile.businessCode" class="eln-badge eln-badge-grey">{{ profile.businessCode }}</span>
      </template>
      <template #right>
        <template v-if="closeReview.available && closeReview.canSubmit">
          <button class="eln-btn-primary" :disabled="closeActionBusy" @click="closeReviewAction('submit')">
            提交完成申请
          </button>
        </template>
        <template v-else-if="closeReview.available && closeReview.canReview">
          <button class="btn-reject" :disabled="closeActionBusy" @click="closeReviewAction('reject')">驳回</button>
          <button class="eln-btn-primary" :disabled="closeActionBusy" @click="closeReviewAction('approve')">
            审核通过并关闭
          </button>
        </template>
        <span v-else-if="closeReview.available && closeReview.note" class="card-note">{{ closeReview.note }}</span>
        <span v-else-if="review.hint" class="card-note">{{ review.hint }}</span>
      </template>
    </PageHeader>

    <div class="task-cols">
      <!-- 左栏-主区 4:733 -->
      <div class="task-main">
        <!-- 卡片-任务信息 4:735 -->
        <section class="card">
          <div class="card-head">
            <h2 class="card-title">任务信息</h2>
          </div>
          <div class="info-row">
            <span class="info-label">所属实验</span>
            <span class="info-value">{{ infoExperiment }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">任务目的</span>
            <span class="info-value">{{ infoPurpose }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">执行计划</span>
            <span class="info-value">{{ infoPlan }}</span>
          </div>
        </section>

        <!-- 卡片-实验记录本 4:748（浅蓝描边强调态；真身是原生 Protocol / Step） -->
        <section class="card card-notebook">
          <div class="card-head">
            <h2 class="card-title">实验记录本 Notebook</h2>
            <span class="eln-badge eln-badge-blue">挂任务层 · DEC-010</span>
            <span class="card-note spacer-right">原生 Protocol / Step · 共 {{ steps.length }} 步</span>
          </div>

          <ol v-if="steps.length" class="step-list">
            <li v-for="(s, i) in steps" :key="i" class="step-item">
              <div class="step-head">
                <span class="step-index">{{ i + 1 }}</span>
                <span class="step-name">{{ s.name }}</span>
                <span class="step-flag" :class="{ done: s.completed }">
                  {{ s.completed ? '已完成' : '未完成' }}
                </span>
                <span v-if="s.completedOn" class="step-time num">{{ s.completedOn }}</span>
              </div>
              <p v-if="s.description" class="rec-text">{{ s.description }}</p>
              <p v-if="s.checklists" class="card-note">清单 {{ s.checklists }} 项</p>
            </li>
          </ol>
          <p v-else class="pane-empty">
            ⓘ 本任务在原生没有 Protocol 步骤（原生 Protocol 挂在任务上，全库 248 个任务里只有 59 个有）。
            这里不留空壳、也不编「5 步流程」。
          </p>
        </section>

        <!-- 卡片-结构化数据录入 4:807 -->
        <section class="card">
          <h2 class="card-title">结构化数据录入</h2>
          <p class="card-note">{{ checklist.note }}</p>
          <div v-if="checklist.fields.length" class="form-grid">
            <div v-for="(f, i) in checklist.fields" :key="i" class="form-field">
              <span class="form-label">{{ f.label }}</span>
              <span class="form-value" :class="{ done: f.value === '已完成' }">{{ f.value }}</span>
            </div>
          </div>
          <p v-else class="pane-empty">
            ⓘ 本任务没有原生 checklist 项 —— 原生只给到「步骤 + 自由文本 + 清单」这三级，
            结构化录入表单属二开（DEC-009），没有真实字段就不画三个假输入框。
          </p>
          <div class="form-submit">
            <button class="btn-sm-primary">保存到记录本</button>
            <span class="card-note">原生 Step 共 {{ checklist.stepCount }} 步</span>
          </div>
        </section>

        <!-- 卡片-任务成果与结论 4:1049 -->
        <section class="card">
          <h2 class="card-title">任务成果与结论</h2>
          <p v-if="!results.length" class="pane-empty">
            ⓘ 本任务原生没有 Result 记录（全库 248 个任务里只有 5 个有），成果留白。
          </p>
          <div v-for="(r, i) in results" :key="i" class="metric-row ok">
            <span class="metric-name">{{ r.name }}</span>
            <span class="metric-result">{{ resultTone(r) }}</span>
          </div>
          <p v-if="conclusion" class="rec-text">{{ conclusion }}</p>
          <p v-else class="pane-empty">
            ⓘ 未填写结论 —— 原生 my_modules 无结论字段，addon 也未给任务档案加该列
            （成果的真值面是上面的 Result），不编。
          </p>
        </section>
      </div>

      <!-- 右栏-属性区 4:734 -->
      <aside class="task-side">
        <!-- 卡片-任务属性 4:827 -->
        <section class="side-card">
          <h2 class="side-title">任务属性</h2>
          <div v-for="p in attributes" :key="p.key" class="attr-row">
            <span class="attr-key">{{ p.key }}</span>
            <span v-if="p.kind === 'chip'" class="eln-badge eln-badge-orange">{{ p.value }}</span>
            <span v-else class="attr-val" :class="p.kind">{{ p.value }}</span>
          </div>
          <p class="card-note">任务关闭后原生自动只读（DEC-003）</p>
        </section>

        <!-- 卡片-流程轨迹 4:849（只挂有真值来源的节点） -->
        <section class="side-card">
          <h2 class="side-title">流程轨迹</h2>
          <div v-for="(f, i) in flow" :key="i" class="flow-item">
            <span class="flow-dot" :class="f.color"></span>
            <div class="flow-body">
              <div class="flow-title" :class="f.color">{{ f.title }}</div>
              <div class="flow-sub" :class="f.color">{{ f.sub }}</div>
            </div>
          </div>
          <p v-if="flowNote" class="card-note">{{ flowNote }}</p>
        </section>

        <!-- 卡片-关联资源 4:876（真身是任务关联的 Repository 行） -->
        <section class="side-card tight">
          <h2 class="side-title">关联资源</h2>
          <div v-for="r in resources" :key="r.name" class="res-row">
            <span class="res-name">{{ r.name }}</span>
            <span class="res-value" :class="{ ok: true }">{{ r.value }}</span>
          </div>
          <p v-if="!resources.length" class="pane-empty tight">
            ⓘ 本任务没有关联的试剂/耗材行（原生 my_module_repository_rows）。
          </p>
          <button class="link-btn">新增资源申请</button>
        </section>

        <!-- 卡片-任务关闭审核（REQ-TASK-CLOSE：状态落在 eln_ui_task_close_requests，不碰原生 my_modules.state） -->
        <section class="side-card tight">
          <h2 class="side-title">任务关闭审核</h2>
          <template v-if="closeReview.available">
            <div class="cr-state">
              <span class="eln-badge" :class="crBadgeClass">{{ closeReview.stateLabel }}</span>
            </div>
            <div v-if="closeReview.submittedBy" class="cr-meta">
              提交人 {{ closeReview.submittedBy }}<span v-if="closeReview.submittedAt" class="num"> · {{ closeReview.submittedAt }}</span>
            </div>
            <div v-if="closeReview.reviewerName" class="cr-meta">
              {{ closeReview.reviewedAt ? '审核人' : '待审人' }} {{ closeReview.reviewerName }}<span v-if="closeReview.reviewedAt" class="num"> · {{ closeReview.reviewedAt }}</span>
            </div>
            <div v-if="closeReview.reason" class="cr-reason">理由：{{ closeReview.reason }}</div>

            <template v-if="closeReview.canSubmit">
              <button class="eln-btn-primary cr-submit" :disabled="closeActionBusy" @click="closeReviewAction('submit')">
                提交完成申请
              </button>
            </template>
            <template v-else-if="closeReview.canReview">
              <textarea v-model="closeReason" class="review-box" placeholder="驳回理由（驳回时必填）"></textarea>
              <div class="review-actions">
                <button class="review-pass" :disabled="closeActionBusy" @click="closeReviewAction('approve')">审核通过并关闭</button>
                <button class="review-reject" :disabled="closeActionBusy" @click="closeReviewAction('reject')">驳回</button>
              </div>
            </template>
            <p v-else-if="closeReview.note" class="card-note cr-note">{{ closeReview.note }}</p>
          </template>
          <p v-else class="pane-empty tight">{{ closeReview.note || '本任务未启用关闭审核。' }}</p>
        </section>

        <!-- 卡片-关联项目指标 4:1077 -->
        <section class="side-card tight">
          <h2 class="side-title">关联项目指标</h2>
          <p class="card-note">本任务产出回写至以下项目级指标（DEC-002）</p>
          <p class="pane-empty tight">
            ⓘ 原生没有项目级指标表，二开也未建 —— 不做假指标行。真值面见「任务成果与结论」。
          </p>
        </section>

        <!-- 卡片-评论沟通 4:1086 -->
        <section class="side-card tight">
          <h2 class="side-title">评论与沟通</h2>
          <div v-if="comments.length" v-for="(c, i) in comments" :key="i" class="comment">
            <div class="comment-head">{{ c.author }} · {{ c.time }}</div>
            <p class="comment-text">{{ c.body }}</p>
          </div>
          <p v-if="!comments.length" class="pane-empty tight">
            ⓘ 本任务还没有原生讨论评论（TaskComment 挂在任务上，全库只有 2 个任务有）。
          </p>
          <div v-if="review.canComment" class="comment-input">
            <input placeholder="输入评论…" />
          </div>
        </section>
      </aside>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import { taskDetail as DEMO } from '../data/mock.js'
// ⚠ 数据来自**共享的响应式 ui**（宿主 entry 写入的那一份），不是组件自己读 window。
//   看 ExperimentDetail.vue 同一套写法：组件只认 ui，window.__ELN_* 归 HostRouterLink。
//   （别学 exp_detail.js 那段注释里的假生效陷阱：塞进 store/ui 前先确认组件真的读。）
import { ui } from '../store/ui'

// ⚠ TDZ：<script setup> 里 `const x = ui.a || DEMO.a` 的 DEMO 必须先声明，
//   否则构建期无报错、运行期 ReferenceError、组件静默不挂载（实验页踩过一次）。
const DEMO_STATUS = '待审核'
const DEMO_SUBTITLE = '任务 MyModule 层 · 实验记录本挂在任务层（DEC-010）· 关闭任务必须项目负责人审核（DEC-003）'
const badgeClass = { pending: 'eln-badge-orange', active: 'eln-badge-blue', done: 'eln-badge-green' }

// ---------- 页头 ----------
// ui.crumb 只有宿主注入了才有；面包屑三段全靠它，取不到就退回原型演示值。
// ⚠ 下钻 URL 优先用 payload 下发的 projectUrl / experimentUrl（服务端唯一真源）；
//   老代码在前端写死 '/projects/:id/eln_project_detail' —— 宿主路由一变就全断。
//   payload 没给才回落，且没有 id 时给 null（当前级不可点），不给假链接。
const crumb = ui.crumb || {}
const crumbs = computed(() => {
  const list = [{ label: '项目列表', to: crumb.listUrl || '/eln_project_list' }]
  if (crumb.projectName)
    list.push({ label: crumb.projectName, to: crumb.projectUrl || null })
  if (crumb.experimentName)
    list.push({ label: crumb.experimentName, to: crumb.experimentUrl || null })
  list.push({ label: taskName.value, to: null })
  return list
})
const taskName = computed(() => ui.taskName || DEMO.name)
const statusCode = computed(() => ui.statusCode || 'pending')
const statusText = computed(() => ui.statusText || DEMO_STATUS)
const statusBadgeClass = computed(() => badgeClass[statusCode.value] || 'eln-badge-grey')
// 原生状态名原样带上：否则「待接收」会让人以为原生真有这一档
const headerSubtitle = computed(() =>
  ui.statusNative
    ? `任务 MyModule #${ui.taskId} · 原生状态「${ui.statusNative}」（默认状态流只有 Not started / In progress / Completed 三档）`
    : DEMO_SUBTITLE
)

// ---------- 任务信息卡（A 原生 / B 二开自有表） ----------
// ⚠ 逐格判空而不是整个覆盖：payload 可能只给了实验名没给目的，
//   整块赋值会把「目的」也抹成演示值（exp_detail.js 同一条教训）。
const info = ui.info || {}
const infoExperiment = info.experiment || DEMO.experiment
const infoPurpose = info.purpose || DEMO.purpose
const infoPlan = info.plan || DEMO.plan
const profile = ui.profile || {}

// ---------- 实验记录本 / 结构化录入（原生 Protocol + Step + checklist） ----------
const steps = ui.steps || []
const checklist = ui.checklist || { note: '', fields: [], stepCount: 0 }

// ---------- 成果 / 讨论 / 资源（原生 Result / TaskComment / RepositoryRow） ----------
const results = ui.results || []
const comments = ui.comments || []
const resources = ui.resources || []

// ---------- 右栏 ----------
const attributes = ui.attributes || []
const flow = ui.flow || []
const flowNote = ui.flowNote || ''
const review = ui.review || { canReview: false, canComplete: false, canComment: false, hint: '' }

// 结论：原生无字段、二开表也没这列 → 留白；只有宿主真给了才显示
const conclusion = ui.conclusion || ''

// ---------- 关闭审核（REQ-TASK-CLOSE / SCN-TASK-CLOSE）：读真值，按钮全部接 actionsUrl ----------
//   available=false → 二开表未部署（老库），整块降级为留白说明，不编演示态。
//   canSubmit（组员可提交）/ canReview（仅项目负责人）/ actionsUrl（端点由服务端下发，前端不写死路由）。
const closeReview = computed(() => ui.closeReview || { available: false })
const crBadgeClass = computed(() => {
  const s = closeReview.value.state
  return {
    none: 'eln-badge-grey',
    pending: 'eln-badge-orange',
    approved: 'eln-badge-green',
    rejected: 'eln-badge-red'
  }[s] || 'eln-badge-grey'
})
// 驳回理由 + 防重复提交
const closeReason = ref('')
const closeActionBusy = ref(false)
async function closeReviewAction(type) {
  const cr = closeReview.value
  if (!cr.available || !cr.actionsUrl) return
  if (type === 'reject' && !closeReason.value.trim()) {
    window.alert('驳回必须填写理由')
    return
  }
  closeActionBusy.value = true
  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')
    const res = await fetch(cr.actionsUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(csrf ? { 'X-CSRF-Token': csrf.content } : {})
      },
      body: JSON.stringify({
        type,
        reason: type === 'reject' ? closeReason.value.trim() : null
      })
    })
    const data = await res.json()
    if (data.ok) {
      // 详情页整页重取 payload（真值渲染审核态/时间线）
      window.location.reload()
    } else {
      window.alert('操作失败：' + (data.error || '未知错误'))
    }
  } catch {
    window.alert('操作失败：网络错误或登录态失效')
  } finally {
    closeActionBusy.value = false
  }
}

function resultTone(r) {
  return r.type === 'Asset' ? '附件' : r.type === 'Table' ? '数据表' : '文本'
}
</script>

<style scoped>
.task-detail {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 4:718 内容区 gap 16 */
}

/* ---------- 面包屑 ---------- */
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
.crumb-current,
.crumb-sep {
  color: var(--color-placeholder);
}

/* ---------- 页头操作按钮 ---------- */
.btn-reject {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  height: 36px;
  padding: 0 14px; /* 画布 4:728 padding 14 */
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  font-weight: 500;
  color: #EF4444;
  flex-shrink: 0;
  transition: background 0.15s ease, border-color 0.15s ease;
}
.btn-reject:hover {
  background: #FEF2F2;
  border-color: #FECACA;
}

/* ---------- 双栏骨架（画布 4:732 gap16 / 4:733、4:734 各 gap14） ---------- */
.task-cols {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}
.task-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.task-side {
  width: 330px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

/* ---------- 左栏卡片（pad20 / r12 / 无描边靠阴影） ---------- */
.card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.card-notebook {
  border: 1px solid #DBEAFE;
}
.card-head {
  display: flex;
  align-items: center;
  gap: 8px;
}
.card-title {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.card-note {
  margin: 0;
  font-size: 11px;
  color: var(--color-placeholder);
  line-height: 1.6;
}
.spacer-right {
  margin-left: auto;
  flex-shrink: 0;
}
.link-btn {
  background: none;
  border: none;
  padding: 0;
  font-size: 12px;
  font-weight: 500;
  color: var(--color-primary);
  flex-shrink: 0;
}
.link-btn:hover {
  text-decoration: underline;
}
.btn-sm-primary {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 34px;
  padding: 0 14px;
  background: var(--color-primary);
  color: #fff;
  border: none;
  border-radius: var(--radius-button);
  font-size: 13px;
  font-weight: 500;
  flex-shrink: 0;
  transition: background 0.15s ease;
}
.btn-sm-primary:hover {
  background: var(--color-primary-hover);
}

/* ---------- 任务信息行 ---------- */
.info-row {
  display: flex;
  gap: 12px;
  align-items: flex-start;
}
.info-label {
  width: 80px;
  flex-shrink: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.info-value {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  color: var(--color-text-menu);
  line-height: 1.6;
}
.info-value.link {
  color: var(--color-primary);
}

/* ---------- 实验记录本：原生 Protocol 步骤（DEC-010 的真身） ---------- */
.step-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.step-item {
  padding: 12px 14px;
  background: #FAFAFA;
  border-radius: 10px;
}
.step-head {
  display: flex;
  align-items: center;
  gap: 8px;
}
.step-index {
  width: 20px;
  height: 20px;
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  background: var(--color-primary);
  color: #fff;
  font-size: 11px;
  font-weight: 600;
}
.step-name {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.step-flag {
  font-size: 10px;
  font-weight: 500;
  padding: 2px 6px;
  border-radius: 4px;
  background: #F4F4F5;
  color: var(--color-subtle-text);
  flex-shrink: 0;
}
.step-flag.done {
  background: #ECFDF5;
  color: #059669;
}
.step-time {
  font-size: 11px;
  color: var(--color-placeholder);
  flex-shrink: 0;
}
.step-item .rec-text {
  margin-top: 6px;
}

/* ---------- 显式留白（取不到真值时的说明块，不许静默空白也不许编） ---------- */
.pane-empty {
  margin: 0;
  padding: 10px 12px;
  background: #FAFAFA;
  border: 1px dashed var(--color-border);
  border-radius: 8px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
}
.pane-empty.tight {
  padding: 8px 10px;
  margin-bottom: 4px;
}

/* ---------- 记录条目（原型遗留，记录本改接原生步骤后本块不再使用） ---------- */
.rec {
  display: flex;
  gap: 12px;
  padding: 14px;
  background: #FAFAFA;
  border-radius: 10px;
}
.rec-rail {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding-top: 3px;
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
.rec-dot.green {
  background: #10B981;
}
.rec-line {
  width: 2px;
  flex: 1;
  min-height: 24px;
  background: var(--color-border);
  border-radius: 1px;
}
.rec-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
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
  font-size: 10px;
  font-weight: 500;
  padding: 2px 6px;
  border-radius: 4px;
  background: #F4F4F5;
  color: var(--color-subtle-text);
}
.rec-type.data {
  background: var(--color-notice-bg);
  color: #92400E;
}
.rec-text {
  margin: 0;
  font-size: 13px;
  color: var(--color-text-menu);
  line-height: 1.6;
}
.num {
  font-family: var(--font-en);
  font-variant-numeric: tabular-nums;
}

/* ---------- 附件 ---------- */
.attach-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.attach {
  display: inline-flex;
  align-items: center;
  height: 26px;
  padding: 0 9px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-small);
  font-size: 11px;
  color: var(--color-subtle-text);
}
.attach.lg {
  height: 28px;
}

/* ---------- 数据对比图（原型遗留：真身已改接原生 Result，本块不再使用） ---------- */
.chart {
  background: #FAFAFA;
  border-radius: 8px;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.chart-title {
  font-size: 11px;
  color: var(--color-text-secondary);
}
.bar-row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.bar-label {
  width: 16px;
  flex-shrink: 0;
  font-size: 11px;
  font-weight: 500;
  color: var(--color-text-secondary);
}
.bar-label.best {
  font-weight: 600;
  color: var(--color-primary);
}
.bar {
  height: 14px;
  border-radius: 7px;
  background: #BFDBFE;
  flex-shrink: 0;
}
.bar.best {
  background: var(--color-primary);
}
.bar-value {
  font-size: 11px;
  color: var(--color-subtle-text);
}
.bar-value.best {
  font-weight: 600;
  color: var(--color-primary);
}

/* ---------- AI 提示条（原型遗留：真身无 AI 结果面，本块不再使用） ---------- */
.ai-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  background: var(--color-role-bg);
  border-radius: 8px;
  padding: 10px 12px;
}
.ai-bar svg {
  color: #7C3AED;
  flex-shrink: 0;
}
.ai-text {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-role-text);
  line-height: 1.5;
}
.ai-action {
  background: none;
  border: none;
  padding: 0;
  font-size: 12px;
  font-weight: 500;
  color: #7C3AED;
  flex-shrink: 0;
}

/* ---------- 结构化数据录入（真身是原生 checklist） ---------- */
.form-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}
.form-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.form-label {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-menu);
}
.form-value {
  height: 38px;
  display: inline-flex;
  align-items: center;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border-strong);
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-text);
}
.form-value.done {
  color: #059669;
}
.form-submit {
  display: flex;
  align-items: center;
  gap: 12px;
}

/* ---------- 达成情况 ---------- */
.metric-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px;
  border-radius: 8px;
}
.metric-row.fail {
  background: #FEF2F2;
}
.metric-row.ok {
  background: #ECFDF5;
}
.metric-name {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-subtle-text);
}
.metric-result {
  font-size: 12px;
  font-weight: 500;
  flex-shrink: 0;
}
.metric-row.fail .metric-result {
  color: #B91C1C;
}
.metric-row.ok .metric-result {
  color: #059669;
}

/* ---------- 右栏卡片（pad18 / r12） ---------- */
.side-card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 18px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
/* 画布 4:827 / 4:849 = gap12；4:876 / 4:888 / 4:1077 / 4:1086 = gap10 */
.side-card.tight {
  gap: 10px;
}
.side-title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.attr-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.attr-key {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.attr-val {
  font-size: 12px;
  color: var(--color-text-menu);
  text-align: right;
}
.attr-val.strong {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.attr-val.mono {
  font-family: var(--font-en);
}
.attr-val.warn {
  font-family: var(--font-en);
  font-weight: 500;
  color: #F59E0B;
}

/* ---------- 流程轨迹 ---------- */
.flow-item {
  display: flex;
  gap: 10px;
  align-items: flex-start;
}
.flow-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  margin-top: 4px;
  flex-shrink: 0;
}
.flow-dot.done {
  background: #10B981;
}
.flow-dot.purple {
  background: #7C3AED;
}
.flow-dot.current {
  background: #F59E0B;
}
.flow-dot.todo {
  background: var(--color-border-strong);
}
.flow-body {
  flex: 1;
  min-width: 0;
}
.flow-title {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text);
}
.flow-title.current {
  color: #B45309;
}
.flow-title.todo {
  font-weight: 400;
  color: var(--color-placeholder);
}
.flow-sub {
  margin-top: 2px;
  font-size: 11px;
  color: var(--color-placeholder);
}
.flow-sub.current {
  color: #F59E0B;
}

/* ---------- 关联资源 / 关联指标 ---------- */
.res-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.res-name {
  font-size: 12px;
  color: var(--color-text-menu);
}
.res-value {
  font-size: 12px;
  font-family: var(--font-en);
  color: var(--color-text-secondary);
  flex-shrink: 0;
}
.res-value.ok {
  font-family: var(--font-sans);
  font-size: 11px;
  color: #10B981;
}
.metric-tone {
  font-size: 12px;
  font-weight: 500;
  flex-shrink: 0;
}
.metric-tone.warn {
  color: #F59E0B;
}
.metric-tone.done {
  color: #10B981;
}

/* ---------- 审核意见 ---------- */
.review-box {
  height: 72px;
  padding: 12px;
  background: #FAFAFA;
  border: 1px solid var(--color-border-strong);
  border-radius: 8px;
  font-size: 12px;
  font-family: inherit;
  color: var(--color-text);
  line-height: 1.6;
  resize: none;
  outline: none;
}
.review-box::placeholder {
  color: var(--color-placeholder);
}
.review-box:focus {
  background: var(--color-card);
  border-color: var(--color-primary);
}
.review-actions {
  display: flex;
  gap: 8px;
}
.review-pass {
  flex: 1;
  height: 36px;
  background: var(--color-primary);
  color: #fff;
  border: none;
  border-radius: var(--radius-button);
  font-size: 12px;
  font-weight: 500;
  transition: background 0.15s ease;
}
.review-pass:hover {
  background: var(--color-primary-hover);
}
.review-reject {
  width: 96px;
  flex-shrink: 0;
  height: 36px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 12px;
  font-weight: 500;
  color: #EF4444;
  transition: background 0.15s ease, border-color 0.15s ease;
}
.review-reject:hover {
  background: #FEF2F2;
  border-color: #FECACA;
}

/* ---------- 任务关闭审核卡（REQ-TASK-CLOSE 真值驱动） ---------- */
.cr-state {
  display: flex;
  align-items: center;
}
.cr-meta {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.cr-reason {
  font-size: 12px;
  color: var(--color-text-menu);
  line-height: 1.6;
  padding: 8px 10px;
  background: #FAFAFA;
  border-radius: 8px;
}
.cr-submit {
  width: 100%;
  height: 36px;
  flex-shrink: 0;
}
.cr-note {
  margin-top: 2px;
}
.eln-badge-red {
  background: #FEF2F2;
  color: #B91C1C;
}

/* ---------- 评论与沟通 ---------- */
/* 画布 4:1088 / 4:1091：gap4 / padding 10（四周等值）/ 灰底 #FAFAFA / r8 */
.comment {
  padding: 10px;
  background: #FAFAFA;
  border-radius: 8px;
}
.comment-head {
  font-size: 11px;
  font-weight: 500;
  color: var(--color-text-secondary);
}
.comment-text {
  margin: 4px 0 0;
  font-size: 12px;
  color: var(--color-text-menu);
  line-height: 1.6;
}
.comment-input {
  display: flex;
  align-items: center;
  height: 34px;
  padding: 0 10px;
  background: #FAFAFA;
  border: 1px solid var(--color-border);
  border-radius: 8px;
}
.comment-input input {
  flex: 1;
  min-width: 0;
  background: none;
  border: none;
  outline: none;
  font-size: 12px;
  font-family: inherit;
  color: var(--color-text);
}
.comment-input input::placeholder {
  color: var(--color-placeholder);
}
</style>
