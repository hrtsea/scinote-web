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
        <span class="eln-badge" :class="pb.status === '已归档' ? 'eln-badge-grey' : 'eln-badge-green'">{{ pb.status }}</span>
        <span class="eln-badge eln-badge-grey badge-metric">{{ pb.metricProgress }}</span>
      </template>
      <template #right>
        <div class="head-actions">
          <button class="eln-btn-ghost pd14">上传任务书</button>
          <button class="eln-btn-primary pd14">编辑项目信息</button>
          <button class="eln-btn-ghost pd14">修改项目状态</button>
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
          <table class="doc-table">
            <thead>
              <tr>
                <th class="eln-th th-check"><span class="checkbox"></span></th>
                <th class="eln-th">实验名称</th>
                <th class="eln-th">状态</th>
                <th class="eln-th">负责人</th>
                <th class="eln-th">任务进度</th>
                <th class="eln-th">截止日期</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="e in experiments" :key="e.id">
                <td class="eln-td td-check"><span class="checkbox"></span></td>
                <td class="eln-td">
                  <router-link :to="drillTo(e, 'experiment')" class="table-link strong">{{ e.fullName }}</router-link>
                </td>
                <td class="eln-td">
                  <span class="status-dot" :style="{ background: statusColor[e.status] }"></span>{{ statusLabel[e.status] }}
                </td>
                <td class="eln-td">
                  <span class="member-cell">
                    <span class="avatar" :style="avatarStyle(e.owner.color)">{{ e.owner.initial }}</span>{{ e.owner.name }}
                  </span>
                </td>
                <td class="eln-td num">{{ e.progress.done }}/{{ e.progress.total }} 任务</td>
                <td class="eln-td num">{{ e.due }}</td>
              </tr>
            </tbody>
          </table>
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
                <button class="eln-btn-primary pd14 sm">编辑</button>
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
                <button class="eln-btn-primary pd14 sm">添加指标</button>
              </div>
              <table class="doc-table">
                <thead>
                  <tr>
                    <th class="eln-th">指标名称</th>
                    <th class="eln-th th-target">目标值</th>
                    <th class="eln-th th-current">当前值</th>
                    <th class="eln-th th-status">状态</th>
                  </tr>
                </thead>
                <tbody v-if="projectMetrics.length">
                  <tr v-for="m in projectMetrics" :key="m.name">
                    <td class="eln-td">{{ m.name }}</td>
                    <td class="eln-td num">{{ m.target }}</td>
                    <td class="eln-td num">{{ m.current }}</td>
                    <td class="eln-td">
                      <span class="eln-badge" :class="m.ok ? 'eln-badge-green' : 'eln-badge-red'">
                        {{ m.ok ? '已达标' : '未达标' }}
                      </span>
                    </td>
                  </tr>
                </tbody>
                <tbody v-else>
                  <tr>
                    <td class="eln-td empty-cell" colspan="4">
                      暂无指标 —— 原生 SciNote 没有项目级指标模型，取不到就不显示（不回落原型演示值）
                    </td>
                  </tr>
                </tbody>
              </table>
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
              <table v-if="taskCloseReview.tasks && taskCloseReview.tasks.length" class="doc-table tcr-table">
                <thead>
                  <tr>
                    <th class="eln-th">任务</th>
                    <th class="eln-th th-status">关闭状态</th>
                    <th class="eln-th th-op">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="t in taskCloseReview.tasks" :key="t.id">
                    <td class="eln-td strong">{{ t.name }}</td>
                    <td class="eln-td">
                      <span class="eln-badge" :class="tcrBadgeClass(t.state)">{{ t.stateLabel }}</span>
                    </td>
                    <td class="eln-td"><a class="table-link" :href="t.detailUrl" target="_blank" rel="noopener">查看任务</a></td>
                  </tr>
                </tbody>
              </table>
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
              <table class="doc-table">
                <thead>
                  <tr>
                    <th class="eln-th">文档分类</th>
                    <th class="eln-th th-status">状态</th>
                    <th class="eln-th th-ver">版本</th>
                    <th class="eln-th th-date">更新时间</th>
                    <th class="eln-th th-op">操作</th>
                  </tr>
                </thead>
                <tbody v-if="requiredDocs.length">
                  <tr v-for="d in requiredDocs" :key="d.name">
                    <td class="eln-td strong">{{ d.name }}</td>
                    <td class="eln-td">
                      <span class="doc-status" :class="d.uploaded ? 'ok' : 'pending'">{{ d.uploaded ? '已上传' : '待上传' }}</span>
                    </td>
                    <td class="eln-td num">{{ d.ver }}</td>
                    <td class="eln-td num">{{ d.date }}</td>
                    <td class="eln-td"><a role="button" tabindex="0" class="table-link" @click.prevent>预览 · 下载</a></td>
                  </tr>
                </tbody>
                <tbody v-else>
                  <tr>
                    <td class="eln-td empty-cell" colspan="5">
                      暂无必传文档 —— 原生 SciNote 没有项目文档分类模型，取不到就不显示
                    </td>
                  </tr>
                </tbody>
              </table>

              <div class="docs-subhead docs-subhead-gap">
                <span class="docs-subhead-title">其他文档</span>
                <span class="block-note flex1">过程记录、参考资料等，随时上传归档</span>
                <button class="eln-btn-primary pd14 sm">上传文档</button>
              </div>
              <table class="doc-table">
                <thead>
                  <tr>
                    <th class="eln-th">文档名称</th>
                    <th class="eln-th">类型</th>
                    <th class="eln-th">上传人</th>
                    <th class="eln-th">上传时间</th>
                    <th class="eln-th">操作</th>
                  </tr>
                </thead>
                <tbody v-if="docs.length">
                  <tr v-for="d in docs" :key="d.name">
                    <td class="eln-td">{{ d.name }}</td>
                    <td class="eln-td">{{ d.type }}</td>
                    <td class="eln-td">{{ d.by }}</td>
                    <td class="eln-td num">{{ d.date }}</td>
                    <td class="eln-td"><a role="button" tabindex="0" class="table-link" @click.prevent>下载</a></td>
                  </tr>
                </tbody>
                <tbody v-else>
                  <tr>
                    <td class="eln-td empty-cell" colspan="5">
                      暂无文档 —— 原生 SciNote 没有项目文档台账，取不到就不显示
                    </td>
                  </tr>
                </tbody>
              </table>
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
              <table class="doc-table">
                <thead>
                  <tr>
                    <th class="eln-th">成员</th>
                    <th class="eln-th">业务称谓</th>
                    <th class="eln-th">UserRole</th>
                    <th class="eln-th">加入时间</th>
                    <th class="eln-th th-op">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="m in members" :key="m.name">
                    <td class="eln-td">
                      <span class="member-cell">
                        <span class="avatar" :style="avatarStyle(m.color)">{{ m.name[0] }}</span>{{ m.name }}
                      </span>
                    </td>
                    <td class="eln-td">{{ m.title }}</td>
                    <td class="eln-td num">{{ m.role }}</td>
                    <td class="eln-td num">{{ m.joined }}</td>
                    <td class="eln-td">
                      <a v-if="m.role !== 'Owner'" role="button" tabindex="0" class="table-link" @click.prevent>变更角色</a>
                      <span v-else class="muted-text">—</span>
                    </td>
                  </tr>
                </tbody>
              </table>
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

              <table v-if="hasCostData" class="doc-table">
                <thead>
                  <tr>
                    <th class="eln-th th-cat">类别</th>
                    <th class="eln-th">数据来源</th>
                    <th class="eln-th">金额算法</th>
                    <th class="eln-th th-amt">金额</th>
                    <th class="eln-th th-amt">占比</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="r in projectCost.rows" :key="r.category">
                    <td class="eln-td strong">{{ r.category }}</td>
                    <td class="eln-td">{{ r.source }}</td>
                    <td class="eln-td">{{ r.basis }}</td>
                    <td class="eln-td num">{{ r.amount }}</td>
                    <td class="eln-td num">{{ r.share }}</td>
                  </tr>
                </tbody>
              </table>

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
  </div>
</template>

<script setup>
import { ref, computed } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
import PageHeader from '../components/PageHeader.vue'
import { drillTo } from '../utils/drill'
import { openHostEndpoint } from '../utils/env'
import { ui } from '../store/ui'
import {
  members,
  experiments,
  statusLabel,
  avatarPalette,
  projectBasic as pb,
  projectMetrics,
  projectCost,
  requiredDocs,
  otherDocs,
  taskCloseReview,
  projectArchive
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

const statusColor = {
  active: 'var(--status-active)',
  notstarted: 'var(--status-notstarted)',
  done: 'var(--status-done)'
}

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

// 任务关闭审核状态 → 徽章配色（spec SCN-PM-IND-3/4/5 状态语义）
function tcrBadgeClass(state) {
  switch (state) {
    case 'approved': return 'eln-badge-green'
    case 'rejected': return 'eln-badge-red'
    case 'pending': return 'eln-badge-grey'
    default: return 'eln-badge-grey'
  }
}

// 项目归档导出（报告 §5 第 6 项 #10 · spec SCN-PM-ARCH-1/2/3）：复用原生 archived 态 + 后端导出端点
function exportArchive() {
  // 宿主端点（SPA 态不存在）：模式判定走 env.js，不再靠 pathname 猜。
  openHostEndpoint(projectArchive.exportUrl)
}

function avatarStyle(color) {
  const c = avatarPalette[color] || avatarPalette.blue
  return { background: c.bg, color: c.fg }
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
</style>
