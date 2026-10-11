<template>
  <!-- 项目详情（画布 4:68 / 4:387）：面包屑 + 页头 + 项目管理区（竖向页签 212 + 内容面板） -->
  <div class="proj-detail">
    <div class="breadcrumb">
      <router-link :to="listUrl || '/eln_project_list'" class="crumb-link">项目列表</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">{{ pb.name }}</span>
    </div>

    <!-- 页头 4:389 -->
    <PageHeader
      :title="pb.name"
      subtitle="项目 Project → 实验 Experiment → 任务 MyModule · 项目管理入口即本页页签（DEC-008）"
    >
      <template #title-extra>
        <!-- ⚠ 不再拿中文文案做相等比较：宿主要是把「已结题」改个说法，配色就静默错了。
             判据换成后端下发的 statusKey。 -->
        <span class="eln-badge" :class="pb.statusKey === 'closed' ? 'eln-badge-grey' : 'eln-badge-green'">{{ pb.status }}</span>
        <span class="eln-badge eln-badge-grey badge-metric">{{ pb.metricProgress }}</span>
      </template>
      <template #right>
        <div class="head-actions">
          <input ref="fileInput" type="file" class="pd-file" @change="onTaskBookPicked" />
          <button
            v-if="can.canUploadDocs"
            class="eln-btn-ghost pd14"
            :disabled="uploading"
            @click="pickTaskBook"
          >{{ uploading ? '上传中…' : '上传任务书' }}</button>
          <button v-if="can.canEditBasic" class="eln-btn-primary pd14" @click="openEdit">编辑项目信息</button>
          <button v-if="can.canChangeStatus" class="eln-btn-ghost pd14" @click="confirmClose">修改项目状态</button>
        </div>
      </template>
    </PageHeader>

    <!-- 项目管理区 4:506 -->
    <div class="pm-card">
      <div class="pm-tabs">
        <button
          v-for="nav in navItems"
          :key="nav.key"
          class="pm-tab"
          :class="{ active: activeNav === nav.key }"
          @click="activeNav = nav.key"
        >
          {{ nav.label }}
        </button>
      </div>
      <div class="pm-divider"></div>

      <div class="pm-content">
        <!-- 实验列表（画布 4:464「卡片-下属实验」为 hidden 态 → 标注来源） -->
        <section v-if="activeNav === 'experiments'" class="tab-section">
          <div class="block-head">
            <h2 class="block-title">下属实验 Experiment</h2>
            <span class="block-note">共 {{ experiments.length }} 个实验 · 任务只挂在实验下（DEC-006）</span>
            <button class="eln-btn-primary pd14 sm">新建实验</button>
          </div>
          <!-- 2026-10-11 换栈：自研 <table> → 宿主 shared/datatable（AG Grid v32.3.9）薄封装。
               与资源中心 5 张表、项目列表同一引擎：列宽可调 / 表头点击排序走服务端 / 分页条在表下。
               行数据由服务端网格端点下发（gridUrl('experiments')），不再从 payload 内联渲染。 -->
          <ResGrid
            v-if="gridUrl('experiments')"
            :data-url="gridUrl('experiments')"
            table-id="pd_experiments"
            :column-defs="experimentsCols"
            height="320px"
          />
          <div v-else class="empty-pane">
            未接入宿主数据端点，暂不渲染表格（原型态）
          </div>
          <p class="src-note">
            ⓘ 画布 4:464 该卡片为 hidden 态；列结构与行数据沿用项目详情「实验列表」同款表格口径，实验名取画布面包屑真值。
          </p>
        </section>

        <template v-else>
          <!-- 子页签栏 6 项（画布 63:105） -->
          <div class="subtabs">
            <button
              v-for="st in subTabs"
              :key="st.key"
              class="subtab"
              :class="{ active: activeSub === st.key }"
              @click="activeSub = st.key"
            >
              {{ st.label }}
            </button>
          </div>
          <div class="subtabs-line"></div>

          <div class="pm-pane">
            <!-- ① 项目基础信息（画布 4:1430，唯一有画布真值的面板） -->
            <section v-if="activeSub === 'basic'" class="pane">
              <div class="block-head">
                <h2 class="block-title">项目基础信息</h2>
                <span class="block-note">项目主数据 · 任何变更写入操作日志（DEC-002）</span>
                <button v-if="can.canEditBasic" class="eln-btn-primary pd14 sm" @click="openEdit">编辑</button>
              </div>
              <div class="field-grid">
                <div class="field-col">
                  <div class="f-item"><span class="f-label">项目名称</span><span class="f-value">{{ pb.name }}</span></div>
                  <div class="f-item"><span class="f-label">项目编号</span><span class="f-value num">{{ pb.code }}</span></div>
                  <div class="f-item"><span class="f-label">起止时间</span><span class="f-value num">{{ pb.span }}</span></div>
                  <div class="f-item"><span class="f-label">项目来源</span><span class="f-value">{{ pb.source }}</span></div>
                  <div class="f-item"><span class="f-label">立项时间</span><span class="f-value num">{{ pb.foundedAt }}</span></div>
                </div>
                <div class="field-col">
                  <div class="f-item"><span class="f-label">项目负责人</span><span class="f-value">{{ pb.owner }}</span></div>
                  <div class="f-item"><span class="f-label">所属团队</span><span class="f-value">{{ pb.team }}</span></div>
                  <div class="f-item"><span class="f-label">项目状态</span><span class="f-value">{{ pb.status }}</span></div>
                </div>
              </div>
              <div class="f-item f-desc">
                <span class="f-label">项目描述</span>
                <span class="f-value">{{ pb.description }}</span>
              </div>
            </section>

            <!-- ② 项目指标（画布 4:416 hidden 态） -->
            <section v-else-if="activeSub === 'kpi'" class="pane">
              <div class="block-head">
                <h2 class="block-title">项目指标</h2>
                <span class="block-note">实验级 DOE 结果在此对齐回写（DEC-002）</span>
                <button v-if="can.canEditBasic" class="eln-btn-primary pd14 sm" @click="openMetricModal(null)">添加指标</button>
              </div>
              <!-- 2026-10-11 换栈：AG Grid（列宽可调 / 服务端排序 / 分页条）。
                   空态判定仍走 payload（与网格行同源 metrics_block）：首屏即可定，
                   不必等端点返回再闪一下空表。 -->
              <div v-if="!projectMetrics.length" class="empty-cell">
                <template v-if="can.canEditBasic">暂无指标，点击右上角「添加指标」登记</template>
                <template v-else>暂无指标</template>
              </div>
              <ResGrid
                v-else-if="gridUrl('metrics')"
                :data-url="gridUrl('metrics')"
                table-id="pd_metrics"
                :column-defs="metricsCols"
                height="240px"
              />
              <div v-else class="empty-pane">未接入宿主数据端点，暂不渲染表格（原型态）</div>
              <p class="src-note">
                ⓘ 画布 4:416 该面板为 hidden 态；条目数（3）与达标数（2）由页头标签锁定（画布 63:4），
                第 1/2 项取任务成果卡实测值（画布 4:1053/4:1054、4:1056/4:1057），第 3 项取项目描述目标（画布 4:1459）。
              </p>

              <!-- 任务关闭审核驱动指标达标（报告 §5 第 6 项 #11 · spec REQ-PM-INDICATOR / SCN-PM-IND-3/4/5）-->
              <div class="block-head" style="margin-top:18px">
                <h2 class="block-title">任务关闭审核</h2>
                <span class="block-note">指标达标由「任务全部关闭」驱动（spec #11）；看板下钻入口已下发</span>
              </div>
              <div class="tcr-summary">
                <span class="tcr-chip">任务总数 <b>{{ taskCloseReview.total }}</b></span>
                <span class="tcr-chip ok">已关闭 <b>{{ taskCloseReview.closed }}</b></span>
                <span class="tcr-chip pending">待审核 <b>{{ taskCloseReview.pending }}</b></span>
                <span class="tcr-chip rejected">驳回 <b>{{ taskCloseReview.rejected }}</b></span>
                <span class="tcr-chip" :class="taskCloseReview.indicatorDriven ? 'ok' : 'warn'">
                  指标驱动 {{ taskCloseReview.indicatorDriven ? '已达成' : '未完成' }}
                </span>
              </div>
              <!-- 2026-10-11 换栈：AG Grid。下钻链接（查看任务）由渲染器的 href 分支承载，
                   detailUrl 仍由服务端下发（前端不拼宿主路径）。 -->
              <ResGrid
                v-if="taskCloseReview.tasks && taskCloseReview.tasks.length && gridUrl('taskCloseReview')"
                :data-url="gridUrl('taskCloseReview')"
                table-id="pd_task_close_review"
                :column-defs="tcrCols"
                height="240px"
              />
              <p v-else class="src-note">
                ⓘ 暂无任务关闭审核记录 —— 原生 SciNote 没有任务关闭审核模型，取不到就不显示（不回落原型演示值）
              </p>
            </section>

            <!-- ③ 项目文档（画布 4:1460 hidden 态） -->
            <section v-else-if="activeSub === 'docs'" class="pane">
              <div class="block-head">
                <h2 class="block-title">项目文档</h2>
                <span class="block-note">立项申请材料、项目任务书、年度计划、年度报告、结题报告为必传，结题归档前必须齐备</span>
              </div>

              <div class="docs-subhead">
                <span class="docs-subhead-title">必传文档</span>
                <span class="block-note flex1">{{ requiredUploaded }}/{{ requiredDocs.length }} 已上传 · 缺失将阻断归档流程</span>
              </div>
              <div v-if="!requiredDocs.length" class="empty-cell">
                暂无必传文档 —— 原生 SciNote 没有项目文档分类模型，取不到就不显示
              </div>
              <ResGrid
                v-else-if="gridUrl('requiredDocs')"
                :data-url="gridUrl('requiredDocs')"
                table-id="pd_required_docs"
                :column-defs="requiredDocsCols"
                height="300px"
              />
              <div v-else class="empty-pane">未接入宿主数据端点，暂不渲染表格（原型态）</div>

              <div class="docs-subhead docs-subhead-gap">
                <span class="docs-subhead-title">其他文档</span>
                <span class="block-note flex1">过程记录、参考资料等，随时上传归档</span>
                <button class="eln-btn-primary pd14 sm">上传文档</button>
              </div>
              <div v-if="!docs.length" class="empty-cell">
                暂无文档 —— 原生 SciNote 没有项目文档台账，取不到就不显示
              </div>
              <ResGrid
                v-else-if="gridUrl('otherDocs')"
                :data-url="gridUrl('otherDocs')"
                table-id="pd_other_docs"
                :column-defs="otherDocsCols"
                height="300px"
              />
              <div v-else class="empty-pane">未接入宿主数据端点，暂不渲染表格（原型态）</div>
              <p class="src-note">
                ⓘ 画布 4:1460 该面板为 hidden 态；必传文档 5 类沿用 REQ-PM-DOCS 立项口径，日期按立项时间（2026-03-02）同源改写。
              </p>
            </section>

            <!-- ④ 项目成员（画布 4:1358 hidden 态） -->
            <section v-else-if="activeSub === 'member'" class="pane">
              <div class="block-head">
                <h2 class="block-title">项目成员</h2>
                <span class="block-note">共 {{ members.length }} 人 · 角色变更即时生效，历史记录留痕（DEC-002）</span>
                <button class="eln-btn-primary pd14 sm">添加成员</button>
              </div>
              <ResGrid
                v-if="gridUrl('members')"
                :data-url="gridUrl('members')"
                table-id="pd_members"
                :column-defs="membersCols"
                height="300px"
              />
              <div v-else class="empty-pane">未接入宿主数据端点，暂不渲染表格（原型态）</div>
              <div class="role-note">
                <AppIcon name="sparkles" :size="16" />
                <span>
                  角色映射自 SciNote UserRole：项目负责人 = Owner、小组组长 = Normal user、组员 = Technician、观察者 = Viewer。
                  权限沿 项目 → 实验 → 任务 继承，可在任意层级覆盖。
                </span>
              </div>
              <p class="src-note">
                ⓘ 画布 4:1358 该面板为 hidden 态；成员与角色取自项目成员数据基座（与实验/任务的指派人不冲突）。
              </p>
            </section>

            <!-- ⑤ 项目花费（画布 79:11 hidden 态） -->
            <section v-else-if="activeSub === 'cost'" class="pane">
              <div class="block-head">
                <h2 class="block-title">项目花费</h2>
                <span class="block-note">按 project_id 汇总消耗 / 执行明细（REQ-RES-CONSUME）</span>
                <div class="scope-switch">
                  <button
                    v-for="s in projectCost.scopes"
                    :key="s.key"
                    class="scope-btn"
                    :class="{ active: costScope === s.key }"
                    @click="costScope = s.key"
                  >
                    {{ s.label }}
                  </button>
                </div>
              </div>

              <div v-if="!hasCostData" class="empty-pane">
                暂无花费数据 —— 花费口径（REQ-RES-CONSUME）尚未在 SciNote 里落地，取不到就不显示（不回落原型演示金额）
              </div>

              <div v-if="hasCostData" class="cost-kpis">
                <div class="cost-kpi total">
                  <span class="ck-label">累计花费</span>
                  <span class="ck-value">{{ projectCost.total }}</span>
                </div>
                <div v-for="s in projectCost.splits" :key="s.label" class="cost-kpi">
                  <span class="ck-label">{{ s.label }}</span>
                  <span class="ck-value num">{{ s.amount }}</span>
                  <span class="ck-sub">占比 {{ s.share }}</span>
                </div>
              </div>

              <ResGrid
                v-if="hasCostData && gridUrl('cost')"
                :data-url="gridUrl('cost')"
                table-id="pd_cost"
                :column-defs="costCols"
                height="260px"
              />

              <div v-if="hasCostData" class="rule-note">
                <AppIcon name="shield" :size="15" />
                <span>{{ projectCost.note }}</span>
              </div>
              <p v-if="hasCostData" class="src-note">
                ⓘ 画布 79:11 该面板为 hidden 态；总额与结构比例取自工作台 KPI「项目总花费 ¥86.4万 · 材料 64% · 测试表征 36%」（画布 4:213），
                口径按 SCN-RES-COST 系列场景，未补造任何条目级明细。
              </p>
            </section>

            <!-- ⑥ 项目归档导出（画布 4:1517 hidden 态） -->
            <section v-else class="pane">
              <div class="block-head">
                <h2 class="block-title">项目归档导出</h2>
                <span class="block-note">按单位归档规范导出完整项目包</span>
                <button class="eln-btn-ghost pd14 sm" :disabled="!projectArchive.canExport || !projectArchive.exportUrl" @click="exportArchive">预览归档包</button>
              </div>
              <div class="archive-check" :class="{ warn: missingDocs.length > 0 }">
                <AppIcon :name="missingDocs.length > 0 ? 'clock' : 'check'" :size="15" />
                <span v-if="!requiredDocs.length">
                  完整性校验不可用：暂无必传文档配置（原生 SciNote 没有项目文档分类模型，不拿原型 5 类文档顶）。
                </span>
                <span v-else-if="missingDocs.length > 0">
                  完整性校验未通过：必传文档 {{ requiredUploaded }}/{{ requiredDocs.length }} 已上传，{{ missingDocs.join('') }}待上传，补齐前归档导出不可用。
                </span>
                <span v-else>
                  完整性校验通过：必传文档 {{ requiredDocs.length }}/{{ requiredDocs.length }} 已上传 · 实验记录完整率 100% · 指标已闭环 · 审批链完备
                </span>
              </div>
              <div v-if="projectArchive.canExport && projectArchive.exportUrl" class="export-cards">
                <div class="export-card">
                  <AppIcon name="archive" :size="18" />
                  <div>
                    <div class="export-name">项目结构化数据归档包（CSV）</div>
                    <div class="export-sub">含项目主数据、实验、成员、花费与关闭审核汇总</div>
                  </div>
                  <button class="export-btn" @click="exportArchive"><AppIcon name="download" :size="14" /></button>
                </div>
              </div>
              <div v-else class="empty-pane">
                暂无归档导出入口 —— 原生项目归档状态未就绪或导出端点未启用，取不到就不显示（不回落原型演示值）
              </div>
              <div class="rule-note">
                <AppIcon name="clock" :size="15" />
                <span>归档包生成后保留 90 天可下载，之后自动转入长期存储（DEC-005）</span>
              </div>
              <p class="src-note">
                ⓘ 画布 4:1517 该面板为 hidden 态；完整性校验联动「项目文档」必传文档与 REQ-PM-ARCHIVE 归档前置条件。
              </p>
            </section>
          </div>
        </template>
      </div>
    </div>

    <!-- ---------- 编辑项目信息（页头三键之一 · 2026-10-11 接线） ---------- -->
    <div v-if="editOpen" class="pd-mask" @click.self="editOpen = false">
      <div class="pd-modal">
        <h3 class="pd-modal-title">编辑项目信息</h3>
        <label class="pd-field">
          <span class="f-label">项目名称</span>
          <input v-model="form.name" class="pd-input" />
        </label>
        <label class="pd-field">
          <span class="f-label">项目编号（原生无此列，存入二开档案）</span>
          <input v-model="form.businessCode" class="pd-input" placeholder="留空则回落系统编号" />
        </label>
        <label class="pd-field">
          <span class="f-label">项目来源（原生无此列，存入二开档案）</span>
          <input v-model="form.source" class="pd-input" placeholder="留空即留白，不编造" />
        </label>
        <!--
          🔴 2026-10-11 ticket 03：这 3 个字段原先是**纯文本** input（placeholder
          "YYYY-MM-DD"），不是原生 type="date"，所以既没有日历也没有格式校验 ——
          用户能敲 "2026/3/1" 或 "下周一" 直接发出去。spec 的 17 处清单只数了
          type="date"，漏了这 3 个；用户报的「eln_project_detail 里点日期框无弹窗」
          就是这里。
        -->
        <label class="pd-field">
          <span class="f-label">立项时间（项目批准日期，非创建时间）</span>
          <!-- 格式提示走 DateField 默认值；"可留空"的语义由上方 label 承担，
               不塞进 placeholder —— 那两个字段（开始/截止）是必填，
               若这里写"未登记则留白"会让人以为整个日期区都可空。 -->
          <DateField v-model="form.approvedOn" data-e2e="pd-approved-on" />
        </label>
        <div class="pd-field-row">
          <label class="pd-field">
            <span class="f-label">开始日期</span>
            <DateField v-model="form.startDate" data-e2e="pd-start" />
          </label>
          <label class="pd-field">
            <span class="f-label">截止日期</span>
            <DateField v-model="form.dueDate" data-e2e="pd-due" />
          </label>
        </div>
        <label class="pd-field">
          <span class="f-label">项目描述</span>
          <textarea v-model="form.description" class="pd-input" rows="3"></textarea>
        </label>
        <p v-if="editError" class="pd-error">{{ editError }}</p>
        <div class="pd-modal-foot">
          <button class="eln-btn-ghost pd14" @click="editOpen = false">取消</button>
          <button class="eln-btn-primary pd14" :disabled="saving" @click="submitEdit">
            {{ saving ? '保存中…' : '保存' }}
          </button>
        </div>
      </div>
    </div>

    <!-- ---------- 项目指标 添加/编辑（2026-10-11 起） ---------- -->
    <!-- 承载面 = 二开表 eln_ui_project_metrics；权限复用 canEditBasic（与编辑项目信息同款）。 -->
    <!-- 创建即未达标，达标只走表格内「切换达标」动作，不进本表单。 -->
    <div v-if="metricOpen" class="pd-mask" @click.self="metricOpen = false">
      <div class="pd-modal">
        <h3 class="pd-modal-title">{{ metricForm.id != null ? '编辑指标' : '添加指标' }}</h3>
        <label class="pd-field">
          <span class="f-label">指标名称</span>
          <input v-model="metricForm.name" class="pd-input" placeholder="必填" />
        </label>
        <label class="pd-field">
          <span class="f-label">目标值</span>
          <input v-model="metricForm.target" class="pd-input" placeholder="如 ≥ 8.0 MPa" />
        </label>
        <label class="pd-field">
          <span class="f-label">当前值</span>
          <input v-model="metricForm.current" class="pd-input" placeholder="如 7.4 MPa" />
        </label>
        <p v-if="metricError" class="pd-error">{{ metricError }}</p>
        <div class="pd-modal-foot">
          <button class="eln-btn-ghost pd14" @click="metricOpen = false">取消</button>
          <button class="eln-btn-primary pd14" :disabled="metricSaving" @click="submitMetric">
            {{ metricSaving ? '保存中…' : '保存' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import DateField from '../components/DateField.vue'
import PageHeader from '../components/PageHeader.vue'
import { openHostEndpoint } from '../utils/env'
import { ui } from '../store/ui'
// 宿主 shared/datatable（AG Grid v32.3.9）薄封装 —— 与资源中心 ResCenter.vue 同一份，
// 本页 6 张表统一走它（2026-10-11 换栈，此前是自研 <table class="doc-table">）。
import ResGrid from './ResGrid.vue'
import ElnLinkRenderer from '../renderers/link_renderer.vue'
import ElnStateBadgeRenderer from '../renderers/state_badge_renderer.vue'
import ElnMemberRenderer from '../renderers/member_renderer.vue'
import ElnRowActionsRenderer from '../renderers/row_actions_renderer.vue'
import {
  members,
  experiments,
  statusLabel,
  projectBasic as pb,
  projectMetrics,
  projectCost,
  requiredDocs,
  otherDocs,
  taskCloseReview,
  projectArchive,
  permissions as can,
  actions as act
} from '../data/mock'

// 面包屑「项目列表」的真实地址：payload 注入了就走 /eln_project_list，
// 没注入（原型独立跑）回落到原型 /projects。空串而不是写死，避免前端绑宿主路由。
const listUrl = computed(() => ui.projectListUrl || '/eln_project_list')

// 两级导航：竖向父级（项目概况 / 实验列表）+ 概况内横向子页签（画布 4:405 / 63:105）
const navItems = [
  { key: 'overview', label: '项目概况' },
  { key: 'experiments', label: '实验列表' }
]
const activeNav = ref('overview')

// 子页签 6 项，顺序照画布 63:105（基础信息 / 指标 / 文档 / 成员 / 花费 / 归档导出）
const subTabs = [
  { key: 'basic', label: '项目基础信息' },
  { key: 'kpi', label: '项目指标' },
  { key: 'docs', label: '项目文档' },
  { key: 'member', label: '项目成员' },
  { key: 'cost', label: '项目花费' },
  { key: 'archive', label: '项目归档导出' }
]
const activeSub = ref('basic')
const costScope = ref('project')

// 状态 → 徽章配色（2026-10-11 换栈后统一用 .eln-badge；此前自研表格用的是 .status-dot 色点）。
// tone 名对应 tokens.css 的 .eln-badge-<tone>。
const experimentBadgeTone = (row) => ({ active: 'blue', done: 'green', notstarted: 'grey' }[row.status] || 'grey')
const metricsBadgeTone = (row) => (row.ok ? 'green' : 'red')
const docsBadgeTone = (row) => (row.uploaded ? 'green' : 'grey')

function tcrBadgeTone(row) {
  switch (row.state) {
    case 'approved': return 'green'
    case 'rejected': return 'red'
    case 'pending': return 'orange'
    default: return 'grey'
  }
}

// ---------- 服务端网格接线（2026-10-11：本页 6 张表换用宿主 AG Grid） ----------
// dataUrl 一律用宿主下发的**完整 URL**（含 ?dataset=），前端零拼接 —— paths 铁律。
// 原型态（无宿主会话）act.grids 不存在 ⇒ gridUrl() 给 null ⇒ 对应表保持原有空态文案，
// 而不是渲染一个永远拉不到数据的空表格。
const grids = computed(() => act.grids || {})

function gridUrl(name) {
  const url = grids.value[name]
  return typeof url === 'string' && url.length > 0 ? url : null
}

// 任务下钻链接（原自研表格是 <a :href="t.detailUrl" target="_blank">）：
// 由渲染器的 href 分支承载，detailUrl 仍来自服务端（不前端拼宿主路径）。
const taskLink = (row) => (row.detailUrl ? [{ label: '查看任务', href: row.detailUrl }] : [])

// 各表列定义。field / valueGetter 取值一律对齐 payload attributes 的键
// （宿主 formatData 会把 attributes 摊平成行对象，故 columnDefs 的键必须与之同名）。
// 纯文本列用 field；需要加工的（状态文案、进度文案）用 colId + valueGetter。
const experimentsCols = computed(() => [
  {
    field: 'fullName',
    headerName: '实验名称',
    minWidth: 220,
    cellRenderer: ElnLinkRenderer,
    cellRendererParams: { urlField: 'detailUrl' }
  },
  {
    colId: 'statusText',
    headerName: '状态',
    width: 120,
    minWidth: 100,
    valueGetter: (p) => statusLabel[p.data.status] || p.data.status,
    cellRenderer: ElnStateBadgeRenderer,
    cellRendererParams: { toneOf: experimentBadgeTone }
  },
  {
    colId: 'ownerName',
    headerName: '负责人',
    minWidth: 150,
    cellRenderer: ElnMemberRenderer,
    cellRendererParams: { sourceField: 'owner' }
  },
  {
    colId: 'progressText',
    headerName: '任务进度',
    width: 130,
    minWidth: 110,
    valueGetter: (p) => {
      const pr = p.data.progress || {}
      return `${pr.done || 0}/${pr.total || 0} 任务`
    }
  },
  { field: 'due', headerName: '截止日期', width: 130, minWidth: 110 }
])

const metricsCols = computed(() => {
  const cols = [
    { field: 'name', headerName: '指标名称', minWidth: 200 },
    { field: 'target', headerName: '目标值', width: 150, minWidth: 110 },
    { field: 'current', headerName: '当前值', width: 150, minWidth: 110 },
    {
      colId: 'statusText',
      headerName: '状态',
      width: 120,
      minWidth: 100,
      valueGetter: (p) => (p.data.ok ? '已达标' : '未达标'),
      cellRenderer: ElnStateBadgeRenderer,
      cellRendererParams: { toneOf: metricsBadgeTone }
    }
  ]
  // 操作列只在有编辑权限时出现（与「添加指标」按钮同一判据 can.canEditBasic）。
  if (can.canEditBasic) {
    cols.push({
      colId: 'actions',
      headerName: '操作',
      sortable: false,
      resizable: false,
      width: 190,
      minWidth: 170,
      cellRenderer: ElnRowActionsRenderer,
      cellRendererParams: {
        actions: [
          { label: '编辑', handler: (row) => openMetricModal(row) },
          { label: '切换达标', handler: (row) => toggleMetric(row) },
          { label: '删除', tone: 'danger', handler: (row) => removeMetric(row) }
        ]
      }
    })
  }
  return cols
})

const requiredDocsCols = computed(() => [
  { field: 'name', headerName: '文档分类', minWidth: 180 },
  {
    colId: 'statusText',
    headerName: '状态',
    width: 120,
    minWidth: 100,
    valueGetter: (p) => (p.data.uploaded ? '已上传' : '待上传'),
    cellRenderer: ElnStateBadgeRenderer,
    cellRendererParams: { toneOf: docsBadgeTone }
  },
  { field: 'ver', headerName: '版本', width: 110, minWidth: 90 },
  { field: 'date', headerName: '更新时间', width: 140, minWidth: 120 },
  {
    colId: 'actions',
    headerName: '操作',
    sortable: false,
    resizable: false,
    width: 140,
    minWidth: 120,
    cellRenderer: ElnRowActionsRenderer,
    // 原页面此处就是 `@click.prevent` 的占位（下载链路未接线）——保持占位语义，不假装能下载。
    cellRendererParams: { actions: [{ label: '预览 · 下载' }] }
  }
])

const otherDocsCols = computed(() => [
  { field: 'name', headerName: '文档名称', minWidth: 200 },
  { field: 'type', headerName: '类型', width: 120, minWidth: 100 },
  { field: 'by', headerName: '上传人', minWidth: 130 },
  { field: 'date', headerName: '上传时间', width: 140, minWidth: 120 },
  {
    colId: 'actions',
    headerName: '操作',
    sortable: false,
    resizable: false,
    width: 110,
    minWidth: 90,
    cellRenderer: ElnRowActionsRenderer,
    cellRendererParams: { actions: [{ label: '下载' }] }
  }
])

const membersCols = computed(() => [
  { field: 'name', headerName: '成员', minWidth: 180, cellRenderer: ElnMemberRenderer },
  { field: 'title', headerName: '业务称谓', minWidth: 130 },
  { field: 'role', headerName: 'UserRole', minWidth: 130 },
  { field: 'joined', headerName: '加入时间', width: 140, minWidth: 120 },
  {
    colId: 'actions',
    headerName: '操作',
    sortable: false,
    resizable: false,
    width: 120,
    minWidth: 100,
    cellRenderer: ElnRowActionsRenderer,
    cellRendererParams: {
      // 原型行为：Owner 不给「变更角色」，显示 —
      actions: (row) => (row.role === 'Owner' ? [{ label: '—', disabled: true }] : [{ label: '变更角色' }])
    }
  }
])

const costCols = computed(() => [
  { field: 'category', headerName: '类别', minWidth: 150 },
  { field: 'source', headerName: '数据来源', minWidth: 260 },
  { field: 'basis', headerName: '金额算法', minWidth: 240 },
  { field: 'amount', headerName: '金额', width: 130, minWidth: 110 },
  { field: 'share', headerName: '占比', width: 110, minWidth: 90 }
])

const tcrCols = computed(() => [
  { field: 'name', headerName: '任务', minWidth: 240 },
  {
    field: 'stateLabel',
    headerName: '关闭状态',
    width: 150,
    minWidth: 120,
    cellRenderer: ElnStateBadgeRenderer,
    cellRendererParams: { toneOf: tcrBadgeTone }
  },
  {
    colId: 'actions',
    headerName: '操作',
    sortable: false,
    resizable: false,
    width: 120,
    minWidth: 100,
    cellRenderer: ElnRowActionsRenderer,
    cellRendererParams: { actions: taskLink }
  }
])

// ⚠ 必传文档 / 其他文档**不再写死在本组件**：原先是组件内常量，嵌入态覆盖不掉，
//   真机上就一直显示「李组员 / 底涂剂选型对比测试报告」这类原型演示值。
//   现在从 mock 引入（原型演示值），嵌入态由宿主注入替换 —— 原生没有项目文档模型，
//   注入的是空数组 → 两个文档面板与归档完整性校验都走**空态**，绝不拿原型文案顶。
const docs = otherDocs
const requiredUploaded = computed(() => requiredDocs.filter((d) => d.uploaded).length)
const missingDocs = computed(() => requiredDocs.filter((d) => !d.uploaded).map((d) => `「${d.name}」`))

// 花费面板有没有真数据：原生/二开都还没落地 REQ-RES-CONSUME → 嵌入态 rows 为空 → 走空态。
// （原型独立跑时 mock.projectCost.rows 有 2 条，面板照原样显示。）
const hasCostData = computed(() => Array.isArray(projectCost.rows) && projectCost.rows.length > 0)

// 项目归档导出（报告 §5 第 6 项 #10 · spec SCN-PM-ARCH-1/2/3）：复用原生 archived 态 + 后端导出端点
function exportArchive() {
  // 宿主端点（SPA 态不存在）：模式判定走 env.js，不再靠 pathname 猜。
  openHostEndpoint(projectArchive.exportUrl)
}

// ---------- 页头三键（2026-10-11 接线） ----------
// 三条纪律：① 端点 URL 一律来自宿主下发（act.*），不自己拼；
//          ② CSRF 与 credentials 沿用 addon 既有写法（ResCenter.vue / ui.js 同款）；
//          ③ 原型独立跑时 act.* 是空串 —— 明说是原型态，不做任何假装的请求。
const fileInput = ref(null)
const editOpen = ref(false)
const saving = ref(false)
const uploading = ref(false)
const editError = ref('')
const form = ref({
  name: pb.name,
  businessCode: pb.code,
  source: pb.source || '',
  // ⚠ 立项时间是**批准日期**，不是 created_at；未登记就留空，由后端留白。
  approvedOn: '',
  startDate: '',
  dueDate: '',
  description: pb.description || ''
})

function hasEndpoint(url) {
  return typeof url === 'string' && url.length > 0
}

function csrfHeader() {
  const token = (document.querySelector('meta[name="csrf-token"]') || {}).content || ''
  return token ? { 'X-CSRF-Token': token } : {}
}

// 宿主返回的非 2xx 通常带 { error: '...' }；也可能是 HTML 错误页 —— 两种都要能读成一句话。
async function failureText(res) {
  const text = await res.text()
  try {
    const parsed = JSON.parse(text)
    return parsed.error || parsed.message || `HTTP ${res.status}`
  } catch (e) {
    return `HTTP ${res.status}`
  }
}

function openEdit() {
  editError.value = hasEndpoint(act.updateProject) ? '' : '原型态未接入宿主端点，编辑不可用'
  editOpen.value = true
}

async function submitEdit() {
  if (!hasEndpoint(act.updateProject)) return

  saving.value = true
  editError.value = ''
  try {
    const res = await fetch(act.updateProject, {
      method: 'PATCH',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', ...csrfHeader() },
      body: JSON.stringify({
        project: {
          name: form.value.name,
          business_code: form.value.businessCode,
          source: form.value.source,
          approved_on: form.value.approvedOn,
          start_date: form.value.startDate,
          due_date: form.value.dueDate,
          description: form.value.description
        }
      })
    })
    if (!res.ok) {
      editError.value = await failureText(res)
      return
    }
    editOpen.value = false
    // 本页没有独立的数据重拉端点 —— 重载是最诚实的刷新（不多造一层假清理逻辑）。
    window.location.reload()
  } catch (e) {
    editError.value = e.message
  } finally {
    saving.value = false
  }
}

// 「修改项目状态」本轮唯一真实的一档是置已结题（= 原生归档）。
// ⚠ 归档后宿主的项目集只认 active，本页不再可读 → 成功就回列表，不让用户停在 404 上。
async function confirmClose() {
  if (!hasEndpoint(act.changeStatus)) return
  if (!window.confirm('置为「已结题」将归档该项目（禁止再新建任务），确定继续？')) return

  const res = await fetch(act.changeStatus, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', ...csrfHeader() },
    body: JSON.stringify({ status: 'closed' })
  })
  if (!res.ok) {
    window.alert(`操作失败：${await failureText(res)}`)
    return
  }
  window.location.href = listUrl.value
}

function pickTaskBook() {
  if (fileInput.value) fileInput.value.click()
}

async function onTaskBookPicked(ev) {
  const file = ev.target.files && ev.target.files[0]
  ev.target.value = ''
  if (!file) return
  if (!hasEndpoint(act.uploadTaskBook)) return

  uploading.value = true
  try {
    const body = new FormData()
    body.append('file', file)
    const res = await fetch(act.uploadTaskBook, {
      method: 'POST',
      credentials: 'same-origin',
      headers: csrfHeader(),
      body
    })
    if (!res.ok) {
      window.alert(`上传失败：${await failureText(res)}`)
      return
    }
    window.location.reload()
  } catch (e) {
    window.alert(`上传失败：${e.message}`)
  } finally {
    uploading.value = false
  }
}

// ---------- 项目指标 CRUD + 达标切换（2026-10-11 起） ----------
// 承载面 = 二开表 eln_ui_project_metrics（原生 projects 无项目级指标模型，与文档/任务审核同属
// 「原生无承载面 → addon 自有表」）。权限复用 canEditBasic（与「编辑项目信息」同款），不另立权限档。
// 创建即未达标（ok 默认 false），达标只走「切换达标」动作，不进创建/编辑表单。
const metricOpen = ref(false)
const metricSaving = ref(false)
const metricError = ref('')
const metricForm = ref({ id: null, name: '', target: '', current: '', actions: null })

function openMetricModal(m) {
  if (!m) {
    metricError.value = hasEndpoint(act.addMetric) ? '' : '原型态未接入宿主端点，添加不可用'
    metricForm.value = { id: null, name: '', target: '', current: '', actions: null }
  } else {
    metricError.value = ''
    metricForm.value = { id: m.id, name: m.name, target: m.target, current: m.current, actions: m.actions }
  }
  metricOpen.value = true
}

async function submitMetric() {
  const isEdit = metricForm.value.id != null
  const url = isEdit ? metricForm.value.actions && metricForm.value.actions.update : act.addMetric
  if (!hasEndpoint(url)) return

  metricSaving.value = true
  metricError.value = ''
  try {
    const res = await fetch(url, {
      method: isEdit ? 'PATCH' : 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', ...csrfHeader() },
      body: JSON.stringify({
        metric: {
          name: metricForm.value.name,
          target: metricForm.value.target,
          current: metricForm.value.current
        }
      })
    })
    if (!res.ok) {
      metricError.value = await failureText(res)
      return
    }
    metricOpen.value = false
    // 重载是最诚实的刷新（payload 全量重算，不多造一层假清理逻辑）。
    window.location.reload()
  } catch (e) {
    metricError.value = e.message
  } finally {
    metricSaving.value = false
  }
}

async function removeMetric(m) {
  if (!hasEndpoint(m.actions && m.actions.destroy)) return
  if (!window.confirm(`确定删除指标「${m.name}」？删除后不可恢复。`)) return

  const res = await fetch(m.actions.destroy, {
    method: 'DELETE',
    credentials: 'same-origin',
    headers: csrfHeader()
  })
  if (!res.ok) {
    window.alert(`删除失败：${await failureText(res)}`)
    return
  }
  window.location.reload()
}

async function toggleMetric(m) {
  if (!hasEndpoint(m.actions && m.actions.toggle)) return
  const res = await fetch(m.actions.toggle, {
    method: 'POST',
    credentials: 'same-origin',
    headers: csrfHeader()
  })
  if (!res.ok) {
    window.alert(`操作失败：${await failureText(res)}`)
    return
  }
  window.location.reload()
}
</script>

<style scoped>
.proj-detail {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 4:387 内容区 gap 16 */
}

/* ---------- 空态（取不到真数据就留白，绝不回落原型演示值） ---------- */
.empty-cell {
  padding: 22px 16px !important;
  text-align: center;
  color: var(--color-placeholder);
  font-size: 12px;
}
.empty-pane {
  padding: 28px 16px;
  border: 1px dashed var(--color-border);
  border-radius: var(--radius-card);
  text-align: center;
  color: var(--color-placeholder);
  font-size: 12px;
  line-height: 1.8;
}

/* ---------- 面包屑 ---------- */
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
.crumb-current,
.crumb-sep {
  color: var(--color-placeholder);
}

/* ---------- 页头操作组（画布 4:396 gap 8） ---------- */
.head-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}
.pd14 {
  padding: 0 14px;
}
.sm {
  height: 34px;
  font-size: 13px;
}
.badge-metric {
  padding: 4px 8px;
  font-size: 12px;
}

/* ---------- 项目管理区（竖向导航 212） ---------- */
.pm-card {
  display: flex;
  align-items: stretch;
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.pm-tabs {
  width: 212px;
  flex-shrink: 0;
  padding: 12px 10px;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 2px;
}
.pm-tab {
  height: 38px;
  padding: 0 10px;
  border: none;
  background: transparent;
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-text-menu);
  text-align: left;
  transition: all 0.12s ease;
}
.pm-tab:hover {
  background: var(--color-fill-soft);
}
.pm-tab.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}
.pm-divider {
  width: 1px;
  flex-shrink: 0;
  background: var(--color-border);
}
.pm-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

/* 子页签栏（画布 63:105：h44 / pad 6-16 / gap 4） */
.subtabs {
  display: flex;
  align-items: center;
  gap: 4px;
  height: 44px;
  padding: 6px 16px;
  flex-shrink: 0;
}
.subtabs-line {
  height: 1px;
  background: var(--color-divider);
  flex-shrink: 0;
}
.subtab {
  height: 32px;
  padding: 0 12px;
  border: none;
  background: transparent;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-text-menu);
  transition: all 0.12s ease;
}
.subtab:hover {
  background: var(--color-fill-soft);
}
.subtab.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}

/* 面板体（画布 4:1430：pad 20 / gap 14） */
.pm-pane {
  display: flex;
  flex-direction: column;
}
.pane {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
/* 画布表格栅格（tokens.css .eln-th/.eln-td）：表格顶到 pane 边缘，20px 内缩由单元格自带。
   `.tab-section` 无内边距（其 .doc-table 无需处理）；`.pane` 有 20px 内边距且内含非表格子块
   （块头 / 表单），故以负边距抵消，使块头与表格首列文字对齐于同一条 20px 基线。 */
.pane .doc-table {
  margin: 0 -20px;
  width: calc(100% + 40px);
}
.pane .f-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

/* 区块头（画布 4:1431：标题 + 说明 + 操作，同行 gap 12） */
.block-head {
  display: flex;
  align-items: center;
  gap: 12px;
}
.block-title {
  margin: 0;
  font-size: 15px;
  font-weight: 500;
  color: var(--color-text);
  line-height: 1.3;
  white-space: nowrap;
}
.block-note {
  font-size: 12px;
  color: var(--color-placeholder);
  line-height: 1.5;
}
.block-head .block-note {
  flex: 1;
  min-width: 0;
}
.flex1 {
  flex: 1;
  min-width: 0;
}

/* 基础信息字段（画布 4:1436 / 4:1437 / 4:1438） */
.field-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
}
.field-col {
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.f-label {
  font-size: 11px;
  color: var(--color-placeholder);
}
.f-value {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
  line-height: 1.6;
}
.f-desc .f-value {
  font-weight: 400;
}
.num {
  font-family: var(--font-en);
  font-variant-numeric: tabular-nums;
}

/* ---------- 通用表 ---------- */
.doc-table {
  width: 100%;
  border-collapse: collapse;
}
.doc-table .eln-th {
  background: var(--color-table-header);
}
.doc-table .eln-td {
  border-bottom: 1px solid var(--color-divider);
}
.doc-table tr:last-child .eln-td {
  border-bottom: none;
}
.table-link {
  font-size: 13px;
  color: var(--color-primary);
  cursor: pointer;
}
.table-link:hover {
  text-decoration: underline;
}
.table-link.strong {
  font-weight: 500;
  color: var(--color-text);
}
.table-link.strong:hover {
  color: var(--color-primary);
}
.table-link.danger {
  color: var(--color-danger, #dc2626);
}
.th-op .table-link {
  margin-right: 8px;
}
.th-op .table-link:last-child {
  margin-right: 0;
}
.muted-text {
  color: var(--color-placeholder);
}
.th-check,
.td-check {
  width: 40px;
}
.th-ver {
  width: 90px;
}
.th-date {
  width: 120px;
}
.th-op {
  width: 100px;
}
.th-target,
.th-current {
  width: 140px;
}
.th-status {
  width: 100px;
}
.th-cat {
  width: 90px;
}
.th-amt {
  width: 110px;
}
.eln-td.strong {
  font-weight: 500;
  color: var(--color-text);
}

/* 来源标注（画布 hidden 态面板） */
.src-note {
  margin: 0;
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-placeholder);
}

.docs-subhead {
  display: flex;
  align-items: center;
  gap: 10px;
}
.docs-subhead-gap {
  margin-top: 10px;
}
.docs-subhead-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
  white-space: nowrap;
}

.member-cell {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.avatar {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  font-size: 11px;
  font-weight: 500;
  flex-shrink: 0;
}

/* ---------- 项目花费 ---------- */
.scope-switch {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
}
.scope-btn {
  height: 28px;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  background: var(--color-card);
  border-radius: 6px;
  font-size: 12px;
  color: var(--color-text-menu);
}
.scope-btn.active {
  background: var(--color-active-bg);
  border-color: var(--color-primary);
  color: var(--color-primary);
  font-weight: 500;
}
.cost-kpis {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}
.cost-kpi {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 14px 16px;
  background: var(--color-fill-soft);
  border-radius: 10px;
}
.ck-label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.ck-value {
  font-size: 22px;
  font-weight: 600;
  color: var(--color-text);
}
.ck-sub {
  font-size: 11px;
  color: var(--color-placeholder);
}
.cost-kpi.total {
  background: var(--color-active-bg);
}
.cost-kpi.total .ck-value {
  color: var(--color-primary);
}

/* ---------- 归档 ---------- */
.archive-check {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  background: #ECFDF5;
  border-radius: 8px;
  font-size: 13px;
  color: #059669;
}
.archive-check svg {
  flex-shrink: 0;
}
.archive-check.warn {
  background: var(--color-notice-bg);
  color: var(--color-notice-text);
}
.archive-check.warn svg {
  color: #E9A845;
}
.doc-status {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 10px;
  font-size: 11px;
  font-weight: 500;
  white-space: nowrap;
}
.doc-status.ok {
  background: #ECFDF5;
  color: #059669;
}
.doc-status.pending {
  background: var(--color-notice-bg);
  color: #B45309;
}
.export-cards {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}
.export-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 16px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 10px;
}
.export-card > svg {
  color: var(--color-primary);
  flex-shrink: 0;
}
.export-card > div {
  flex: 1;
  min-width: 0;
}
.export-name {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.export-sub {
  font-size: 11px;
  color: var(--color-placeholder);
  margin-top: 2px;
}
.export-btn {
  width: 30px;
  height: 30px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  background: var(--color-card);
  color: var(--color-primary);
  flex-shrink: 0;
}
.export-btn:hover {
  background: var(--color-active-bg);
}

/* ---------- 任务关闭审核汇总（报告 §5 第 6 项 #11） ---------- */
.tcr-summary {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.tcr-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  background: var(--color-fill-soft);
  border-radius: 999px;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.tcr-chip b {
  font-weight: 600;
  color: var(--color-text);
}
.tcr-chip.ok {
  background: #ECFDF5;
  color: #059669;
}
.tcr-chip.ok b {
  color: #059669;
}
.tcr-chip.pending {
  background: var(--color-notice-bg);
  color: #B45309;
}
.tcr-chip.rejected {
  background: #FEF2F2;
  color: #DC2626;
}
.tcr-chip.warn {
  background: var(--color-notice-bg);
  color: #B45309;
}
.tcr-table {
  margin-top: 4px;
}

/* ---------- 口径 / 规则说明条 ---------- */
.rule-note {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 12px 14px;
  background: var(--color-fill-soft);
  border-radius: 10px;
  font-size: 12px;
  color: var(--color-subtle-text);
  line-height: 1.7;
}
.rule-note svg {
  flex-shrink: 0;
  margin-top: 2px;
  color: var(--color-primary);
}

/* 角色说明卡（#F5F0FF） */
.role-note {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 12px 14px;
  background: var(--color-role-bg);
  border-radius: 10px;
  font-size: 12px;
  color: var(--color-role-text);
  line-height: 1.7;
}
.role-note svg {
  flex-shrink: 0;
  margin-top: 2px;
}

/* ---------- 编辑项目信息弹层（页头三键接线，2026-10-11） ---------- */
.pd-file {
  display: none;
}
.pd-mask {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}
.pd-modal {
  width: 520px;
  max-width: 92vw;
  max-height: 88vh;
  overflow: auto;
  padding: 20px;
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.pd-modal-title {
  margin: 0;
  font-size: 15px;
  font-weight: 500;
  color: var(--color-text);
}
.pd-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.pd-field-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
/* 🔴 2026-10-11 ticket 03：详情页这三个日期换成了 DateField，
   而 DateField 的 lg 默认是 36px / radius 8px，本页 .pd-input 是 34px / 6px ——
   不对齐就会在同一个弹窗里出现「输入框比旁边的框高 2px」的错位。
   必须用 :deep()：DateField 的 .date-field__input 带的是**它自己**的 data-v，
   本组件的 scoped 属性不会落到那个 input 上。 */
.pd-field :deep(.date-field__input) {
  height: 34px !important;
  border-radius: 6px !important;
  padding-left: 30px !important;
  padding-right: 30px !important;
}
.pd-input {
  height: 34px;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-text);
  background: var(--color-card);
}
textarea.pd-input {
  height: auto;
  padding: 8px 10px;
  line-height: 1.6;
  font-family: inherit;
}
.pd-error {
  margin: 0;
  font-size: 12px;
  color: #DC2626;
}
.pd-modal-foot {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
