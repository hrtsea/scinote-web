<template>
  <!-- 资源中心总览（画布 79:253 / PRD §7.9.1）：四页签独立面板切换 -->
  <div class="rc-page">
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">资源中心</span>
    </div>

    <PageHeader
      title="资源中心"
      :subtitle="applySubtitle"
      show-navigator
      @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
    />

    <!-- 页签栏（34 高浅蓝底选中） -->
    <div class="rc-tabs">
      <button
        v-for="t in tabs"
        :key="t.key"
        class="rc-tab"
        :class="{ active: activeTab === t.key }"
        @click="activeTab = t.key"
      >{{ t.label }}</button>
    </div>

    <!-- ================= 页签 1：资源台账（宿主原生 Inventories 列表组件） ================= -->
    <section v-if="activeTab === 'inventory'" class="rc-panel">
      <div class="rc-block-head">
        <h3 class="rc-block-title">资源台账</h3>
        <span class="rc-block-note">原生 Inventories 列表组件（RepositoriesTable）：行管理 / Stock 与有效期 / 列自定义 / 筛选归档均在同一组件内完成</span>
      </div>
      <!-- 真机：直接渲染宿主原生 `repositories/table.vue` —— 与 /repositories 是**同一份源码、
           同一批接口**，靠服务端注入的 inventory.native 传 URL / 状态（见 ResCenterController
           #native_repository_props）。2026-10-09 换承载：过去由 ERB 把该组件渲染在
           #eln-res-center **之外**、另起第二个 Vue app，再由 syncNativeRepoHost 切 display
           （挂着「宿主节点必须在挂载点外 / 两 script 先后顺序 / 显隐不归 Vue3」三条脆弱约束）；
           现在由本页自己的 app 直接渲染 —— 功能零损失，页面只剩一个 Vue app。 -->
      <div v-if="nativeRepos" class="rc-card rc-card--grid">
        <div class="rc-native-repo-host">
          <RepositoriesTable
            :data-source="nativeRepos.dataSource"
            :actions-url="nativeRepos.actionsUrl"
            :create-url="nativeRepos.createUrl"
            :active-page-url="nativeRepos.activePageUrl"
            :archived-page-url="nativeRepos.archivedPageUrl"
            :current-view-mode="nativeRepos.currentViewMode"
            :user-roles-url="nativeRepos.userRolesUrl"
          />
        </div>
      </div>
      <!-- 离线原型（独立 SPA 跑，无宿主、无原生接口）回落 mock 卡片 —— 真机绝不显示。 -->
      <template v-else>
        <div class="rc-inv-grid">
          <a v-for="r in inventoryRepos" :key="r.id" class="rc-inv-card" :href="`/repositories/${r.id}`">
            <div class="rc-inv-name">{{ r.name }}</div>
            <div class="rc-inv-desc">{{ r.description || '—' }}</div>
            <div class="rc-inv-meta">
              <span class="rc-inv-count">{{ r.rowsCount }} 条目</span>
              <span class="rc-inv-link">打开原生库存 →</span>
            </div>
          </a>
        </div>
        <p v-if="!inventoryRepos.length" class="rc-footnote">当前团队暂无可访问的原生库存（Inventories）</p>
      </template>
    </section>

    <!-- ================= 页签 2：出入库记录 ================= -->
    <section v-else-if="activeTab === 'ledger'" class="rc-panel">
      <div class="rc-block-head">
        <h3 class="rc-block-title">出入库记录</h3>
        <span class="rc-block-note">出库＝原生任务消耗，写快照单价；入库不计入花费（SCN-RES-COST-4）</span>
      </div>
      <!-- 筛选行（与「消耗 / 执行明细」同款四维：类型 / 项目 / 操作人 / 日期范围） -->
      <div class="rc-filter">
        <div class="rc-filter-controls">
          <select v-model="ledgerFilterType" class="rc-select" aria-label="按类型筛选">
            <option value="">全部类型</option>
            <option value="出库">出库</option>
            <option value="入库">入库</option>
          </select>
          <select v-model="ledgerFilterProject" class="rc-select" aria-label="按项目筛选">
            <option value="">全部项目</option>
            <option v-for="p in ledgerFilterProjects" :key="p" :value="p">{{ p }}</option>
          </select>
          <select v-model="ledgerFilterUser" class="rc-select" aria-label="按操作人筛选">
            <option value="">全部操作人</option>
            <option v-for="u in ledgerFilterUsers" :key="u" :value="u">{{ u }}</option>
          </select>
          <input v-model="ledgerFilterFrom" type="date" class="rc-date" aria-label="起始日期" />
          <span class="rc-filter-sep">~</span>
          <input v-model="ledgerFilterTo" type="date" class="rc-date" aria-label="截止日期" />
          <button class="rc-filter-reset" @click="resetLedgerFilter">重置</button>
        </div>
      </div>
      <div class="rc-card rc-card--grid">
        <ResGrid
          :data-url="'/eln_res_center/grid?dataset=ledger'"
          table-id="rc_ledger"
          :column-defs="ledgerColDefs"
          :post-params="ledgerPostParams"
          :reloading-table="ledgerReloadNonce"
        />
        <div class="rc-card-foot">
          出入库记录由服务端分页加载；入库不写项目与花费，出库按任务消耗自动登记快照单价（SCN-RES-COST-4）
        </div>
      </div>
    </section>

    <!-- ================= 页签 2：消耗 / 执行明细 ================= -->
    <section v-else-if="activeTab === 'consume'" class="rc-panel">
      <div class="rc-block-head">
        <h3 class="rc-block-title">消耗 / 执行明细</h3>
        <span class="rc-block-note">物资行由原生任务消耗同步登记；服务行不写 Ledger（SCN-RES-CONSUME-1/2）</span>
      </div>
      <div class="rc-filter">
        <div class="rc-filter-controls">
          <select v-model="filterType" class="rc-select" aria-label="按类型筛选">
            <option value="">全部类型</option>
            <option value="material">物资</option>
            <option value="service">服务</option>
          </select>
          <select v-model="filterProjectId" class="rc-select" aria-label="按项目筛选">
            <option value="">全部项目</option>
            <option v-for="p in consumeFilterProjects" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
          <select v-model="filterUserId" class="rc-select" aria-label="按操作人筛选">
            <option value="">全部操作人</option>
            <option v-for="u in consumeFilterUsers" :key="u.id" :value="u.id">{{ u.name }}</option>
          </select>
          <input v-model="filterFrom" type="date" class="rc-date" aria-label="起始日期" />
          <span class="rc-filter-sep">~</span>
          <input v-model="filterTo" type="date" class="rc-date" aria-label="截止日期" />
          <button class="rc-filter-reset" @click="resetConsumeFilter">重置</button>
        </div>
        <button class="rc-filter-export" @click="exportConsume">导出 CSV</button>
      </div>
      <div class="rc-card rc-card--grid">
        <ResGrid
          :data-url="'/eln_res_center/grid?dataset=consume'"
          table-id="rc_consume"
          :column-defs="consumeColDefs"
          :post-params="consumePostParams"
          :reloading-table="consumeReloadNonce"
        />
      </div>
    </section>

    <!-- ================= 页签 3：资源申请 ================= -->
    <section v-else-if="activeTab === 'apply'" class="rc-panel">
      <div class="rc-block-head">
        <h3 class="rc-block-title">资源申请单</h3>
        <span class="rc-block-note">二段式审批：小组组长初审 → 项目负责人终审；未通过不计入花费（SCN-RES-APPROVE-5）</span>
      </div>
      <div class="rc-filter">
        <div class="rc-filter-controls">
          <select v-model="applyFilterStatus" class="rc-select" aria-label="按状态筛选">
            <option value="">全部状态</option>
            <option v-for="s in applyFilterOptions.statuses" :key="s.value" :value="s.value">{{ s.label }}</option>
          </select>
          <select v-model="applyFilterKind" class="rc-select" aria-label="按资源类型筛选">
            <option value="">全部类型</option>
            <option v-for="t in applyFilterOptions.types" :key="t.value" :value="t.value">{{ t.label }}</option>
          </select>
          <select v-model="applyFilterProjectId" class="rc-select" aria-label="按项目筛选">
            <option value="">全部项目</option>
            <option v-for="p in applyFilterOptions.projects" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
          <select v-model="applyFilterSubmitterId" class="rc-select" aria-label="按提交人筛选">
            <option value="">全部提交人</option>
            <option v-for="u in applyFilterOptions.submitters" :key="u.id" :value="u.id">{{ u.name }}</option>
          </select>
          <button class="rc-filter-reset" @click="resetApplyFilter">重置</button>
        </div>
        <button class="rc-filter-export" @click="showApplyForm = !showApplyForm">＋ 新建申请</button>
      </div>
      <!-- 行内新建表单（SCN-RES-APPLY-1）：直建草稿，编号自动生成，提交后跳详情页 -->
      <div v-if="showApplyForm" class="rc-form-card">
        <div class="rc-form-title">新建资源申请</div>
        <div class="rc-form-grid">
          <label class="rc-field">
            <span class="rc-field-label">申请项目 *</span>
            <select v-model="form.projectId" class="rc-input" @change="onProjectChanged">
              <option value="">请选择项目</option>
              <option v-for="p in applyProjects" :key="p.id" :value="p.id">{{ p.name }}</option>
            </select>
          </label>
          <label class="rc-field">
            <span class="rc-field-label">资源类型 *</span>
            <select v-model="form.kind" class="rc-input" @change="onKindChanged">
              <option value="material">材料</option>
              <option value="service">测试表征</option>
            </select>
          </label>
          <!-- 服务类必须选档案条目：单价与「是否需验收」都取自档案快照（spec：档案是服务目录的唯一载体），
               不在这里留手填单价的口子。 -->
          <label v-if="form.kind === 'service'" class="rc-field">
            <span class="rc-field-label">服务档案 *</span>
            <select v-model="form.serviceCatalogId" class="rc-input" @change="onServiceCatalogPicked">
              <option value="">请选择服务档案条目</option>
              <option v-for="c in applyServiceCatalogs" :key="c.id" :value="c.id">
                {{ c.name }} · ¥{{ c.unitPrice }}/次{{ c.requiresAcceptance ? ' · 需验收' : ' · 不需验收' }}
              </option>
            </select>
          </label>
          <!-- 材料类 = **请购单**（ADR-0030）：申请的是「买什么、买多少、进哪个库」，
               不是「从库里领哪条」。货到了才由终审人在详情页执行「到货验收入库」。 -->
          <label v-if="form.kind === 'material'" class="rc-field">
            <span class="rc-field-label">目标库（进入哪个库）*</span>
            <select v-model="form.repositoryId" class="rc-input">
              <option value="">请选择这批料到货后进入哪个库</option>
              <option v-for="r in applyRepositories" :key="r.id" :value="r.id">
                {{ r.name }}
              </option>
            </select>
            <!-- 下拉为空必须说清楚「下一步该做什么」，否则用户只会看到一堆选不了的空框。
                 库是**申请时**选、不是验收时选：申请人最清楚这批料该进哪。
                 （库还必须有「库存」列，否则入库时会被后端拒绝并给出可行动文案。） -->
            <span v-if="!applyRepositories.length" class="rc-field-warn">
              本团队暂无可选库 —— 请先到「库存仓库」新建一个库并添加「库存」列，再回来申请。
            </span>
          </label>
          <label v-if="form.kind === 'material'" class="rc-field">
            <span class="rc-field-label">预计消耗任务</span>
            <select v-model="form.myModuleId" class="rc-input" @change="onMyModulePicked">
              <option value="">（选填）这批料预计用在哪次实验</option>
              <option v-for="m in applyMyModulesForProject" :key="m.id" :value="m.id">
                {{ m.name }} · {{ m.projectName }}
              </option>
            </select>
            <!-- 选填（SCN-RES-APPLY-1「可填写关联任务」）：请购时常常还不知道具体消耗在哪个任务。
                 选了它，详情页的消耗溯源会精确到该任务；不选则退化为「这条料上的全部消耗」。 -->
            <span v-if="form.projectId && !applyMyModulesForProject.length" class="rc-field-warn">
              该项目下还没有任务 —— 可以留空，不影响申请。
            </span>
          </label>
          <label class="rc-field">
            <span class="rc-field-label">资源名称 *</span>
            <input v-model="form.name" class="rc-input" placeholder="如：PP 基料 K8003" />
          </label>
          <label class="rc-field">
            <span class="rc-field-label">数量 *</span>
            <input v-model="form.qty" class="rc-input" type="number" min="0" step="any" placeholder="> 0" />
          </label>
          <label class="rc-field">
            <span class="rc-field-label">单位</span>
            <input v-model="form.unit" class="rc-input" placeholder="kg / L / 次（选填）" />
          </label>
          <label class="rc-field">
            <span class="rc-field-label">单价（快照）</span>
            <input v-model="form.unitPrice" class="rc-input" type="number" min="0" step="any"
                   :readonly="form.kind === 'service'"
                   :placeholder="form.kind === 'service' ? '由服务档案固定' : '¥ / 单位（选填）'" />
          </label>
        </div>
        <label class="rc-field">
          <span class="rc-field-label">用途</span>
          <textarea v-model="form.purpose" class="rc-input rc-textarea" rows="2" placeholder="选填：申请用途说明"></textarea>
        </label>
        <div class="rc-form-actions">
          <span class="rc-form-error">{{ formError }}</span>
          <button class="rc-btn-primary" :disabled="formBusy" @click="submitApply">{{ formBusy ? '保存中…' : '保存草稿' }}</button>
          <button class="rc-btn-ghost" :disabled="formBusy" @click="closeApplyForm">取消</button>
        </div>
        <div class="rc-form-hint">保存为草稿后，在申请详情页点「提交审批」进入二段式审批流；编号自动生成（SQ-YYYY-NNNN）</div>
      </div>
      <div class="rc-card rc-card--grid">
        <!--
          资源申请单表格 —— 与资源中心其余 4 张表统一为宿主 shared/datatable/table.vue
          （AG Grid v32.3.9，与 /projects 同款）。四维筛选经 postParams 下发服务端，
          可见范围仍由 ResCenterPayload / ResourceApprovalPolicy 收口（安全边界在服务端）。
        -->
        <ResGrid
          :data-url="'/eln_res_center/grid?dataset=apply'"
          table-id="rc_apply"
          :column-defs="applyColDefs"
          :post-params="applyPostParams"
          :reloading-table="applyReloadNonce"
        />
        <div class="rc-card-foot">
          提交人可见本人申请与审批流转记录（SCN-RES-APPLY-3）；终审通过后材料出库、测试表征获得执行许可
        </div>
      </div>

      <!-- ============ 审批人配置面板（仅项目负责人可见，REQ-RES-APPROVER Q6-1） ============ -->
      <div v-if="applyCanConfigureApprovers" class="rc-card rc-apr">
        <div class="rc-apr-head">
          <div class="rc-apr-title">审批人配置</div>
          <button class="rc-filter-export" @click="toggleApproverPanel">
            {{ showApproverPanel ? '收起' : '展开配置' }}
          </button>
        </div>
        <div v-if="showApproverPanel" class="rc-apr-body">
          <div v-if="approverError" class="rc-form-error">{{ approverError }}</div>
          <div class="rc-apr-toolbar">
            <label class="rc-field" style="flex-direction:row;align-items:center;gap:8px;">
              <span class="rc-field-label">项目</span>
              <select v-model="approverProjectId" class="rc-input" @change="onApproverProjectChanged">
                <option v-for="p in (approverPanel ? approverPanel.projects : [])" :key="p.id" :value="p.id">{{ p.name }}</option>
              </select>
            </label>
            <button class="rc-btn-ghost" :disabled="approverBusy" @click="initApprovers"
                    title="把项目负责人写进「初审 / 终审」两阶段；不写「验货」——验货人须单独指定">一键初始化（负责人填初审·终审）</button>
          </div>
          <div v-for="(stageData, stageKey) in (approverPanel ? approverPanel.stages : {})" :key="stageKey" class="rc-apr-stage">
            <div class="rc-apr-stage-head">
              <span class="rc-apr-stage-label">{{ stageData.label }}<span v-if="!stageData.configured" class="rc-apr-unconf">（未配置）</span></span>
              <select v-model="stageAddUser[stageKey]" class="rc-select">
                <option value="">＋ 添加审批人…</option>
                <option v-for="c in (approverPanel ? approverPanel.candidates : [])" :key="c.id" :value="c.id">{{ c.name }}</option>
              </select>
              <button class="rc-btn-primary" :disabled="!stageAddUser[stageKey] || approverBusy"
                      @click="addApprover(stageKey, stageAddUser[stageKey]); stageAddUser[stageKey]=''">添加</button>
            </div>
            <div class="rc-apr-users">
              <span v-for="u in stageData.users" :key="u.id" class="rc-apr-chip">
                {{ u.name }}
                <button class="rc-apr-chip-x" :disabled="approverBusy" @click="removeApprover(u.id)" title="移除">×</button>
              </span>
              <span v-if="!stageData.users.length" class="rc-apr-empty">{{ stageKey === 'receipt' ? '暂无验货人（未配置则无人可验，材料单会卡在待验货）' : '暂无审批人' }}</span>
            </div>
          </div>
          <!-- 到货验收的项目级策略（REQ-RES-RECEIPT · ADR-0032 D3） -->
          <div class="rc-apr-stage">
            <div class="rc-apr-stage-head">
              <span class="rc-apr-stage-label">验货策略</span>
              <label class="rc-apr-self">
                <input type="checkbox" v-model="allowSelfVerification"
                       :disabled="approverBusy" @change="saveAllowSelfVerification" />
                <span>允许验货人验收<b>自己</b>提交的申请单</span>
              </label>
            </div>
            <div class="rc-apr-hint">
              关闭时：验货人不能验收自己的单（默认，fail-closed）。开启仅在「小团队、验货人就是申请人」时需要 ——
              开启后等于放弃「自己上传照片自己验」这层互相校验。
              <span v-if="!receiptPolicyPersisted">当前使用默认值（不允许自验），尚未显式保存。</span>
            </div>
          </div>
          <ul v-if="approverPanel && approverPanel.warnings && approverPanel.warnings.length" class="rc-apr-warn">
            <li v-for="(w, i) in approverPanel.warnings" :key="i">{{ w }}</li>
          </ul>
        </div>
      </div>
    </section>

    <!-- ================= 页签 4：项目花费 ================= -->
    <section v-else class="rc-panel">
      <div class="rc-block-head">
        <h3 class="rc-block-title">项目花费</h3>
        <span class="rc-block-note">金额＝Σ(数量×快照单价)；三口径：按项目 / 按成员 / 按项目+成员；设备模板库存不计花费（SCN-RES-COST-6）</span>
      </div>

      <div class="rc-stats">
        <div v-for="s in costStats" :key="s.label" class="rc-stat">
          <div class="rc-stat-label">{{ s.label }}</div>
          <div class="rc-stat-value">{{ s.value }}</div>
        </div>
      </div>

      <!-- 三方对账行：花费 ↔ 消耗明细 ↔ 出入库（口径恒等闸门，后端 reconciliation 块） -->
      <div class="rc-recon" :class="{ 'rc-recon-bad': costRecon && !costRecon.consistent }">
        <template v-if="costRecon">
          对账：明细物资 {{ costRecon.detailMaterialRows }} 笔 / 出入库流水消耗 {{ costRecon.ledgerMaterialRows }} 笔 ·
          明细 {{ costRecon.detailMaterialTotal }} · 流水 {{ costRecon.ledgerMaterialTotal }} ——
          {{ costRecon.consistent ? '一一对应 ✓' : '口径不一致 ✗（请检查）' }}
        </template>
      </div>

      <div class="rc-sub">
        <div class="rc-block-head">
          <h3 class="rc-block-title">按项目汇总</h3>
          <span class="rc-block-note">按 project_id 归集（SCN-RES-COST-1）；入库采购额不计入</span>
        </div>
        <div class="rc-card rc-card--grid">
          <ResGrid
            :data-url="'/eln_res_center/grid?dataset=by_project'"
            table-id="rc_by_project"
            :column-defs="byProjectColDefs"
            :height="'360px'"
          />
        </div>
      </div>

      <div class="rc-sub">
        <div class="rc-block-head">
          <h3 class="rc-block-title">按成员汇总</h3>
          <span class="rc-block-note">按 user_id 归集（SCN-RES-COST-5）；与项目筛选可组合（项目+成员口径）</span>
        </div>
        <div class="rc-card rc-card--grid">
          <ResGrid
            :data-url="'/eln_res_center/grid?dataset=by_member'"
            table-id="rc_by_member"
            :column-defs="byMemberColDefs"
            :height="'360px'"
          />
        </div>
      </div>

      <p class="rc-footnote">
        口径切换：按项目 / 按成员 / 项目+成员；仅统计已计入花费的明细行——待验收服务行暂不计入，设备模板库存恒不参与（SCN-RES-COST-6）
      </p>
    </section>
  </div>
</template>

<script setup>
import { ref, computed, reactive, watch } from 'vue/dist/vue.esm-bundler.js'
import PageHeader from '../components/PageHeader.vue'
// 资源中心 5 张表统一薄封装：宿主 shared/datatable/table.vue（AG Grid v32.3.9，与 /projects 同款）
import ResGrid from './ResGrid.vue'
// 资源台账页签 = 宿主原生 Inventories 列表组件（与 /repositories 同一份源码、同一批接口）。
// 经 webpack 别名 `host`（→ app/javascript/vue）引用宿主 **非 shared 目录** 的组件；
// 解析到同一绝对路径 ⇒ 与 addon 侧 `shared/datatable/table.vue` 是同一个模块实例。
import RepositoriesTable from 'host/repositories/table.vue'
// 申请编号列下钻链接渲染器（AG Grid cellRenderer；目标 URL 由后端 apply_row 下发）
import ElnLinkRenderer from '../renderers/link_renderer.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'
import { navigate, openHostEndpoint } from '../utils/env'
import { resCenterPayload } from '../data/mock'

const validKeys = ['inventory', 'ledger', 'consume', 'apply', 'cost']
// tab 参数双通道：嵌入宿主是普通 query（location.search），独立 SPA 是 hash 路由
// （#/...?tab=xxx）—— 2026-10-04 实测：只读 hash 时真机 /eln_res_center?tab=ledger
// 从未生效过（旧 verify 没测直开所以没暴露）。
const urlTab = ((location.search.match(/tab=(\w+)/) || location.hash.match(/tab=(\w+)/) || [])[1]) ||
               (resCenterPayload.defaultTab || 'inventory')
const activeTab = ref(validKeys.includes(urlTab) ? urlTab : 'inventory')

const tabs = [
  { key: 'inventory', label: '资源台账' },
  { key: 'ledger', label: '出入库记录' },
  { key: 'consume', label: '消耗 / 执行明细' },
  { key: 'apply', label: '资源申请' },
  { key: 'cost', label: '项目花费' }
]

// ---- 5 个 tab 数据：真机由 src/entries/res_center.js 注入（resCenterPayload） ----
const inventoryRepos = (resCenterPayload.inventory && resCenterPayload.inventory.repositories) || []
// 资源台账：宿主原生 RepositoriesTable 所需的 URL / 状态（服务端注入，见 controller
// #native_repository_props）。缺省 ⇒ 独立 SPA（无宿主、无原生接口）→ 回落 mock 卡片。
const nativeRepos = (resCenterPayload.inventory && resCenterPayload.inventory.native) || null
const costStats = resCenterPayload.cost.stats
const costRecon = resCenterPayload.cost.reconciliation

// ---- 消耗/执行明细筛选 + 导出（报告 §5 第 6 项 #12）----
// 下拉选项由 payload.consume.projects / .users 注入（带 id，供导出回传）；嵌入态为空数组。
const consumeFilterProjects = resCenterPayload.consume.projects || []
const consumeFilterUsers = resCenterPayload.consume.users || []

const filterType = ref('')        // '' | 'material' | 'service'
const filterProjectId = ref('')
const filterUserId = ref('')
const filterFrom = ref('')
const filterTo = ref('')

function resetConsumeFilter() {
  filterType.value = ''
  filterProjectId.value = ''
  filterUserId.value = ''
  filterFrom.value = ''
  filterTo.value = ''
}

// 导出：把当前筛选条件作为 query 传给后端 /eln_res_center/export（服务端全量口径 CSV）。
// 嵌入态走宿主绝对路径；独立 SPA 用 hash 路由同款写法。
function exportConsume() {
  const params = new URLSearchParams()
  if (filterType.value) params.set('type', filterType.value)
  if (filterProjectId.value) params.set('project_id', filterProjectId.value)
  if (filterUserId.value) params.set('user_id', filterUserId.value)
  if (filterFrom.value) params.set('range_from', filterFrom.value)
  if (filterTo.value) params.set('range_to', filterTo.value)
  const qs = params.toString()
  const url = '/eln_res_center/export' + (qs ? '?' + qs : '')
  // 宿主端点（SPA 态没有这个端点）：模式判定走 env.js，不再靠 pathname 猜。
  openHostEndpoint(url)
}

// ---- 出入库记录筛选（类型 / 项目 / 操作人 / 日期范围，四维与「消耗 / 执行明细」同款）----
// 候选从**已加载的流水行**里抽（与展示同一份数据）：下拉里出现的条件必定筛得出结果，
// 不会出现「选了却空表」的怪态。明细页签的候选改走后端全量范围，是因为它还要喂服务端导出；
// 本页签没有导出，候选与展示同源即可，也就顺手省掉一条筛选口径不一致的路。
// ⚠ 代价同明细页签的展示侧：流水由 payload 侧 limit 200 截断，候选也止于这 200 行。
const ledgerFilterType = ref('')      // '' | '出库' | '入库'
const ledgerFilterProject = ref('')
const ledgerFilterUser = ref('')
const ledgerFilterFrom = ref('')
const ledgerFilterTo = ref('')

// 出入库筛选用候选：改由后端 payload.ledger.filterOptions 下发（与网格同源，
// 覆盖 team 范围内全量流水，不受前端展示截断影响；占位串已在服务端剔除）。
const ledgerFilterProjects = computed(() => (resCenterPayload.ledger.filterOptions.projects || []))
const ledgerFilterUsers = computed(() => (resCenterPayload.ledger.filterOptions.users || []))

function resetLedgerFilter() {
  ledgerFilterType.value = ''
  ledgerFilterProject.value = ''
  ledgerFilterUser.value = ''
  ledgerFilterFrom.value = ''
  ledgerFilterTo.value = ''
}

// ---- 资源台账页签：原生组件已由本页 app 直接渲染（见模板），不再需要显隐开关 ----
// 2026-10-09 换承载前这里有一段 syncNativeRepoHost：ERB 把原生列表渲染在
// #eln-res-center 之外、另挂一个 Vue app，Vue3 只能切外层容器 display。
// 现在组件就在本 app 的模板里（v-if="nativeRepos"），显隐由 Vue 自己管，那段已删。

// ---- 新建申请表单（SCN-RES-APPLY-1）----
// projects 下拉数据源：真机由 payload.apply.projects 注入，独立跑用 mock 值
const applyProjects = (resCenterPayload.apply && resCenterPayload.apply.projects) || []
// 服务档案（真机由 payload.apply.serviceCatalogs 下发；独立跑用空数组 → 下拉为空只提示，不回落演示数据）
const applyServiceCatalogs = (resCenterPayload.apply && resCenterPayload.apply.serviceCatalogs) || []
// 材料类下拉：目标库 + 预计消耗任务（真机由 payload.apply.repositories / .myModules 下发）
// 🔴 是「库」(repositories) 不是「库存条目」(repositoryRows)：材料类＝请购单，
//   料还没进库，货到了才入库（ADR-0030）。旧字段 repositoryRows 已从后端删除。
const applyRepositories = (resCenterPayload.apply && resCenterPayload.apply.repositories) || []
const applyMyModules = (resCenterPayload.apply && resCenterPayload.apply.myModules) || []
const showApplyForm = ref(false)
const formBusy = ref(false)
const formError = ref('')
const emptyForm = () => ({
  projectId: '', kind: 'material', name: '', qty: '', unit: '', unitPrice: '', purpose: '',
  serviceCatalogId: '', repositoryId: '', myModuleId: ''
})
const form = ref(emptyForm())

// 消耗任务下拉只列「所选项目下」的任务 —— 后端 create_draft 校验
// `my_module.experiment.project_id == project.id`，不筛选就是让用户先选错再吃 422。
// 未选项目时退回全量（label 里带项目名，选完把项目对齐过去，见 onMyModulePicked）。
const applyMyModulesForProject = computed(() => {
  if (!form.value.projectId) return applyMyModules
  return applyMyModules.filter((m) => String(m.projectId) === String(form.value.projectId))
})

function onProjectChanged() {
  // 换项目 → 旧任务必然不属于新项目，先清掉，免得带着提交
  form.value.myModuleId = ''
}

function onMyModulePicked() {
  const m = applyMyModules.find((x) => String(x.id) === String(form.value.myModuleId))
  if (!m) return
  // 任务归属项目即申请项目（后端按这条校验），没选项目就顺手补上
  if (!form.value.projectId) form.value.projectId = m.projectId
}

// 类型切到「测试表征」：先清掉上一形态填的价，免得材料手填的单价被当成服务的单价带上单；
// 服务类不建库存、不入额度（SCN-RES-APPROVE-4），目标库一并清掉。
function onKindChanged() {
  form.value.serviceCatalogId = ''
  if (form.value.kind === 'service') {
    form.value.unitPrice = ''
    form.value.repositoryId = ''
    form.value.myModuleId = ''
  }
}

// 选中档案即把「名称 / 单位 / 单价」刷成档案值 —— 服务的单价不允许手填，
// 登记服务行时也只能取档案快照（两端同一处取值，花费页才说得清这钱从哪来）
function onServiceCatalogPicked() {
  const c = applyServiceCatalogs.find((x) => String(x.id) === String(form.value.serviceCatalogId))
  if (!c) return
  form.value.name = c.name
  form.value.unit = '次'
  form.value.unitPrice = c.unitPrice
}

function closeApplyForm() {
  showApplyForm.value = false
  formError.value = ''
  form.value = emptyForm()
}

async function submitApply() {
  formError.value = ''
  // 前端先挡一遍必填（后端 Workflow.create_draft 才是真校验）
  if (!form.value.projectId) { formError.value = '请选择申请项目'; return }
  if (!String(form.value.name || '').trim()) { formError.value = '请填写资源名称'; return }
  const qtyNum = parseFloat(form.value.qty)
  if (!Number.isFinite(qtyNum) || qtyNum <= 0) { formError.value = '数量必须大于 0'; return }
  // 服务类必须绑档案：后端 create_draft 才是真校验（同一条规则），这里先挡一遍省一次往返
  if (form.value.kind === 'service' && !String(form.value.serviceCatalogId || '').trim()) {
    formError.value = '请选择测试表征服务档案条目'; return
  }
  // 材料类必须选「进入哪个库」（ADR-0030 D7）：申请时选定，货到了才入库到该库。
  // 后端 create_draft 才是真校验，这里先挡一遍省一次往返。
  if (form.value.kind === 'material' && !String(form.value.repositoryId || '').trim()) {
    formError.value = '请选择材料到货后进入的目标库'; return
  }
  // 预计消耗任务**选填**（SCN-RES-APPLY-1「可填写关联任务」）：请购时未必知道用在哪次实验。
  // 选了只影响详情页消耗溯源的精度，不影响申请本身能否提交。

  formBusy.value = true
  try {
    // CSRF：与申请详情页操作条同款——读 meta csrf-token 塞请求头
    const token = (document.querySelector('meta[name="csrf-token"]') || {}).content || ''
    const resp = await fetch('/eln_res_applications', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
      body: JSON.stringify({
        project_id: form.value.projectId,
        kind: form.value.kind,
        name: String(form.value.name || '').trim(),
        qty: form.value.qty === '' ? null : qtyNum,
        unit: String(form.value.unit || '').trim(),
        unit_price: (form.value.unitPrice === '' || form.value.unitPrice == null) ? null : parseFloat(form.value.unitPrice),
        service_catalog_id: form.value.serviceCatalogId || null,
        // 材料类：目标**库**（请购语义——料还没进库）+ 预计消耗任务（选填）。
        // 服务类不传（服务不建库存、不入额度，SCN-RES-APPROVE-4）。
        repository_id: form.value.repositoryId || null,
        my_module_id: form.value.myModuleId || null,
        purpose: String(form.value.purpose || '').trim()
      })
    })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || !data.ok) {
      formError.value = data.error || '保存失败，请稍后再试'
      return
    }
    // 成功：跳新单详情页。
    // ★ 路径词汇表统一后，两种模式是**同一串路径**（宿主真实路由），
    //   只是跳法不同：内嵌态整页跳（Rails 接管），SPA 态交给 hash 路由。
    //   统一出口见 src/utils/env.js#navigate —— 不再在此手工拼 '#/res-apply/…'。
    navigate('/eln_res_apply/' + encodeURIComponent(data.no))
  } catch (e) {
    formError.value = '网络异常，请稍后再试'
  } finally {
    formBusy.value = false
  }
}

// ---- 资源申请页签：四维客户端筛选（Q4-2：可见范围服务端已收口，这里只做展示层过滤）----
const applyFilterStatus = ref('')
const applyFilterKind = ref('')
const applyFilterProjectId = ref('')
const applyFilterSubmitterId = ref('')

const applyFilterOptions = computed(() => {
  const fo = (resCenterPayload.apply && resCenterPayload.apply.filterOptions) || {}
  return {
    statuses: fo.statuses || [],
    types: fo.types || [],
    projects: fo.projects || [],
    submitters: fo.submitters || []
  }
})

function resetApplyFilter() {
  applyFilterStatus.value = ''
  applyFilterKind.value = ''
  applyFilterProjectId.value = ''
  applyFilterSubmitterId.value = ''
}

// 页头副标题随可见范围切换（REQ-RESOURCE · SCN-RES-1~3）
const applyPermissions = computed(() => (resCenterPayload.apply && resCenterPayload.apply.permissions) || {})
const applySubtitle = computed(() => {
  if (applyPermissions.value.scope === 'manage') {
    return '项目负责人可管理审批人配置；组员仅查看本人申请的审批流转记录（REQ-RESOURCE · SCN-RES-1~3）'
  }
  return '组员仅查看本人申请的审批流转记录（REQ-RESOURCE · SCN-RES-1~3）'
})

// ---- 审批人配置面板（仅项目负责人可见；REQ-RES-APPROVER Q6-1）----
// 真机由 GET/POST/DELETE /eln_project_approvers 驱动；独立预览无后端时用 approverSeed 兜底渲染。
const applyCanConfigureApprovers = computed(() => !!applyPermissions.value.canConfigureApprovers)
const showApproverPanel = ref(false)
const approverBusy = ref(false)
const approverError = ref('')
const approverPanel = ref(null)
const approverProjectId = ref('')
// ⚠ 刻意**不硬编码** { group: '', project: '' }：阶段集合由后端 ProjectApprover::STAGES
//   驱动（V1.28 加了 receipt 验货阶段）。硬编码的坏处是「新阶段在面板上加不进去」——
//   而症状是下拉能选人、点了却因为 v-model 绑不上而静默无反应。
//   这里用 Proxy 惰性建键：v-model 读写任意阶段名都能落进这个对象。
const stageAddUser = reactive(new Proxy({}, { get: (t, k) => (k in t ? t[k] : ''), set: (t, k, v) => ((t[k] = v), true) }))

function approverCsrf() {
  return (document.querySelector('meta[name="csrf-token"]') || {}).content || ''
}

function loadApproverPanel(projectId) {
  approverProjectId.value = projectId
  const seed = (resCenterPayload.apply && resCenterPayload.apply.approverSeed) || null
  // 先以 mock 种子兜底（独立预览无后端也能渲染），再尝试拉真机数据覆盖
  if (seed) { approverPanel.value = JSON.parse(JSON.stringify(seed)); syncReceiptPolicyFromPanel(approverPanel.value) }
  const url = '/eln_project_approvers' + (projectId ? ('?project_id=' + encodeURIComponent(projectId)) : '')
  fetch(url, { headers: { 'X-CSRF-Token': approverCsrf() } })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (data && data.projects) { approverPanel.value = data; syncReceiptPolicyFromPanel(data) }
    })
    .catch(() => { /* 独立预览：保留 mock 种子 */ })
}

function onApproverProjectChanged() {
  loadApproverPanel(approverProjectId.value)
}

async function addApprover(stage, userId) {
  if (!userId) return
  approverBusy.value = true
  approverError.value = ''
  try {
    const resp = await fetch('/eln_project_approvers', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': approverCsrf() },
      body: JSON.stringify({ project_id: approverProjectId.value, stage: stage, user_id: userId })
    })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || !data.ok) { approverError.value = data.error || '添加失败'; return }
    if (data.payload) approverPanel.value = data.payload
  } catch (e) {
    approverError.value = '网络异常，请稍后再试'
  } finally {
    approverBusy.value = false
  }
}

// u.id = 审批人**行** id（与后端 ProjectApproversPayload.user_row 暴露的 id 一致，DELETE 端点要它）
async function removeApprover(approverId) {
  approverBusy.value = true
  approverError.value = ''
  try {
    const resp = await fetch('/eln_project_approvers/' + encodeURIComponent(approverId), {
      method: 'DELETE',
      headers: { 'X-CSRF-Token': approverCsrf() }
    })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || !data.ok) { approverError.value = data.error || '移除失败'; return }
    if (data.payload) approverPanel.value = data.payload
  } catch (e) {
    approverError.value = '网络异常，请稍后再试'
  } finally {
    approverBusy.value = false
  }
}

// D3 · ADR-0032：本项目是否允许验货人验自己的申请单。
// ⚠ 默认 false（没落库行就是「不允许」），所以开关默认是**关**的 —— fail-closed 方向。
const allowSelfVerification = ref(false)
const receiptPolicyPersisted = ref(false)

// 独立预览（mock）时也要能渲染面板，故缺 receiptPolicy 键时回落到「未持久化 + 不允许」
function syncReceiptPolicyFromPanel(panel) {
  const p = panel && panel.receiptPolicy
  allowSelfVerification.value = !!(p && p.allowSelfVerification)
  receiptPolicyPersisted.value = !!(p && p.persisted)
}

async function saveAllowSelfVerification() {
  approverBusy.value = true
  approverError.value = ''
  try {
    const resp = await fetch('/eln_project_approvers/receipt_policy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': approverCsrf() },
      // ⚠ 显式转布尔再发：v-model 给的是 true/false，但这里若将来被 checkbox 的
      //   "0"/"1" 语义污染，后端会当成 truthy 字符串。后端已用 Boolean cast 兜底，
      //   发送侧也保持一致，两边都不依赖对方的隐式转换。
      body: JSON.stringify({ project_id: approverProjectId.value, allow_self_verification: !!allowSelfVerification.value })
    })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || !data.ok) { approverError.value = data.error || '保存失败'; return }
    if (data.payload) { approverPanel.value = data.payload }
    syncReceiptPolicyFromPanel(data.payload || approverPanel.value)
  } catch (e) {
    approverError.value = '网络异常，请稍后再试'
  } finally {
    approverBusy.value = false
  }
}

async function initApprovers() {
  approverBusy.value = true
  approverError.value = ''
  try {
    const resp = await fetch('/eln_project_approvers/init', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': approverCsrf() },
      body: JSON.stringify({ project_id: approverProjectId.value })
    })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || !data.ok) { approverError.value = data.error || '初始化失败'; return }
    if (data.payload) { approverPanel.value = data.payload; syncReceiptPolicyFromPanel(data.payload) }
  } catch (e) {
    approverError.value = '网络异常，请稍后再试'
  } finally {
    approverBusy.value = false
  }
}

function toggleApproverPanel() {
  showApproverPanel.value = !showApproverPanel.value
  if (showApproverPanel.value) {
    const first = (approverPanel.value && approverPanel.value.projects && approverPanel.value.projects[0] && approverPanel.value.projects[0].id) ||
                  (applyPermissions.value.manageableProjectIds && applyPermissions.value.manageableProjectIds[0])
    loadApproverPanel(first || '')
  }
}

// ============================================================
// 资源中心 5 张表 —— 宿主 shared/datatable/table.vue 列定义与筛选下发
// ============================================================

// 状态列着色（与旧手写表一致）：已完成/已通过/已结算→绿，待审批/待验收→橙，驳回→红，—→灰
function statusCellStyle(p) {
  const s = p.value
  if (s === '—') return { color: '#A1A1AA' }
  if (s === '已完成' || s === '已通过' || s === '已结算') return { color: '#16A34A', fontWeight: 500 }
  if (s === '待审批' || s === '待验收') return { color: '#E9A845', fontWeight: 500 }
  if (s === '驳回') return { color: '#DF3562', fontWeight: 500 }
  return { color: '#2F6FED' }
}

// ---- 出入库记录 ----
const ledgerColDefs = [
  { field: 'time', headerName: '时间', width: 140, sortable: true },
  { field: 'type', headerName: '类型', width: 90, sortable: true, cellStyle: (p) => ({ color: p.value === '出库' ? '#DF3562' : '#2F6FED', fontWeight: 500 }) },
  { field: 'name', headerName: '名称', minWidth: 160, flex: 1 },
  { field: 'qty', headerName: '数量', width: 110, sortable: true },
  { field: 'price', headerName: '快照单价', width: 120, sortable: true },
  { field: 'project', headerName: '关联项目', width: 200, sortable: true },
  { field: 'user', headerName: '操作人', width: 90, sortable: true }
]
const ledgerPostParams = computed(() => ({
  type: ledgerFilterType.value,
  project: ledgerFilterProject.value,
  user: ledgerFilterUser.value,
  range_from: ledgerFilterFrom.value,
  range_to: ledgerFilterTo.value
}))
const ledgerReloadNonce = ref(0)
watch(ledgerPostParams, () => { ledgerReloadNonce.value += 1 })

// ---- 消耗 / 执行明细 ----
const consumeColDefs = [
  { field: 'time', headerName: '时间', width: 130, sortable: true },
  { field: 'type', headerName: '类型', width: 80, sortable: true, cellStyle: (p) => ({ color: p.value === '服务' ? '#6F2DC1' : '#2F6FED', fontWeight: 500 }) },
  { field: 'name', headerName: '名称', minWidth: 160, flex: 1 },
  { field: 'qty', headerName: '数量', width: 90, sortable: true },
  { field: 'price', headerName: '单价（快照）', width: 120, sortable: true },
  { field: 'amount', headerName: '金额', width: 110, sortable: true },
  { field: 'project', headerName: '关联项目', width: 180, sortable: true },
  { field: 'user', headerName: '操作人', width: 80, sortable: true },
  { field: 'status', headerName: '结果状态', width: 100, sortable: true, cellStyle: statusCellStyle }
]
const consumePostParams = computed(() => ({
  type: filterType.value === 'material' ? 'material' : filterType.value === 'service' ? 'service' : '',
  project_id: filterProjectId.value,
  user_id: filterUserId.value,
  range_from: filterFrom.value,
  range_to: filterTo.value
}))
const consumeReloadNonce = ref(0)
watch(consumePostParams, () => { consumeReloadNonce.value += 1 })

// ---- 按项目汇总 ----
const byProjectColDefs = [
  { field: 'name', headerName: '项目', minWidth: 160, flex: 1, sortable: true },
  { field: 'count', headerName: '消耗笔数', width: 90, sortable: true },
  { field: 'material', headerName: '物资消耗', width: 140, sortable: true },
  { field: 'service', headerName: '服务执行', width: 140, sortable: true },
  { field: 'total', headerName: '合计金额', width: 140, sortable: true },
  { field: 'ratio', headerName: '占比', width: 90, sortable: true }
]

// ---- 按成员汇总 ----
const byMemberColDefs = [
  { field: 'name', headerName: '成员', minWidth: 120, flex: 1, sortable: true },
  { field: 'count', headerName: '笔数', width: 90, sortable: true },
  { field: 'project', headerName: '关联项目', minWidth: 140, flex: 1, sortable: true },
  { field: 'material', headerName: '物资消耗', width: 140, sortable: true },
  { field: 'service', headerName: '服务执行', width: 140, sortable: true },
  { field: 'total', headerName: '合计金额', width: 140, sortable: true }
]

// ---- 资源申请单 ----
const applyColDefs = [
  {
    field: 'no',
    headerName: '申请编号',
    width: 130,
    sortable: true,
    // 「申请编号」可点下钻到申请详情。原型是
    //   `<router-link :to="`/eln_res_apply/${a.no}`">`（ELN系统-Vue3/src/views/ResCenter.vue L325），
    // 2026-10-09 换 AG Grid 后丢了。目标地址由后端按行下发（apply_row 的 detailUrl），
    // 前端只渲染不拼路由；取不到时渲染器回落纯文本。
    cellRenderer: ElnLinkRenderer
  },
  { field: 'type', headerName: '类型', minWidth: 160, flex: 1, sortable: true },
  { field: 'project', headerName: '项目', width: 140, sortable: true },
  { field: 'qty', headerName: '数量', width: 90, sortable: true },
  { field: 'status', headerName: '状态', width: 90, sortable: true, cellStyle: statusCellStyle },
  { field: 'user', headerName: '提交人', width: 90, sortable: true },
  { field: 'time', headerName: '提交时间', width: 130, sortable: true }
]
const applyPostParams = computed(() => ({
  status: applyFilterStatus.value,
  kind: applyFilterKind.value,
  project_id: applyFilterProjectId.value,
  submitter_id: applyFilterSubmitterId.value
}))
const applyReloadNonce = ref(0)
watch(applyPostParams, () => { applyReloadNonce.value += 1 })
</script>

<style scoped>
.rc-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:256 内容区 gap 16 */
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

/* 页签（画布 79:264：34 高 / 内边距 14 / 圆角 8 / 选中浅蓝底） */
.rc-tabs {
  display: flex;
  gap: 4px;
}
.rc-tab {
  height: 34px;
  padding: 0 14px;
  background: none;
  border: none;
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-subtle-text);
  transition: background 0.15s ease, color 0.15s ease;
}
.rc-tab:hover {
  background: var(--color-fill-soft);
  color: var(--color-text);
}
.rc-tab.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}

/* 原生库存入口卡片（资源台账 tab 完全采用原生 Inventories） */
.rc-inv-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 16px;
}
.rc-inv-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 18px 20px;
  text-decoration: none;
  color: inherit;
  transition: box-shadow 0.15s ease, transform 0.15s ease;
}
.rc-inv-card:hover {
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.10);
  transform: translateY(-1px);
}
.rc-inv-name {
  font-size: 14px;
  font-weight: 500;
  color: var(--color-text);
}
.rc-inv-desc {
  font-size: 12px;
  line-height: 1.6;
  color: var(--color-text-secondary);
  min-height: 19px;
}
.rc-inv-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 4px;
}
.rc-inv-count {
  font-size: 12px;
  color: var(--color-placeholder);
}
.rc-inv-link {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-primary);
}

/* 区块 */
.rc-panel {
  /* 页签内容容器（画布 79:352 / 79:424 / 79:483）：面板级 gap 16 */
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.rc-block,
.rc-sub {
  /* 语义区块（画布 79:275 / 79:311 / 79:497 / 79:522）：区块内 gap 10 */
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.rc-block-head {
  display: flex;
  align-items: baseline;
  gap: 12px;
}
.rc-block-title {
  margin: 0;
  font-size: 15px;
  font-weight: 500;
  color: var(--color-text);
  white-space: nowrap;
}
.rc-block-note {
  font-size: 12px;
  line-height: 1.6;
  color: var(--color-placeholder); /* 画布 79:355 / 79:427 区块说明 #A1A1AA */
}

/* 筛选行 */
.rc-filter {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.rc-filter-text {
  font-size: 12px;
  color: var(--color-text-secondary); /* 画布 79:357 / 79:429 筛选提示 #71717A */
}
.rc-filter-export {
  background: none;
  border: none;
  padding: 0;
  font-size: 12px;
  font-weight: 500;
  color: var(--color-primary);
}
.rc-filter-export:hover {
  text-decoration: underline;
}

/* 真实筛选控件（报告 §5 第 6 项 #12） */
.rc-filter-controls {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.rc-select,
.rc-date {
  height: 30px;
  padding: 0 8px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 12px;
  color: var(--color-text);
  background: var(--color-card);
  box-sizing: border-box;
}
.rc-select:focus,
.rc-date:focus {
  outline: none;
  border-color: var(--color-primary);
}
.rc-filter-sep {
  font-size: 12px;
  color: var(--color-placeholder);
}
.rc-filter-reset {
  height: 30px;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  background: var(--color-card);
  font-size: 12px;
  color: var(--color-text-secondary);
  cursor: pointer;
}
.rc-filter-reset:hover {
  color: var(--color-primary);
  border-color: var(--color-primary);
}

/* 表格卡片 */
.rc-card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}

/* 行内新建表单（SCN-RES-APPLY-1） */
.rc-form-card {
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 18px 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rc-form-title {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.rc-form-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px 16px;
}
.rc-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.rc-field-label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
/* 下拉为空时的解释文案：宁可多一行字，也不要让用户对着空下拉猜为什么提交不了 */
.rc-field-warn {
  margin-top: 4px;
  font-size: 12px;
  line-height: 1.5;
  color: #C2410C;
}
.rc-input {
  height: 32px;
  padding: 0 10px;
  border: 1px solid #E4E4E7;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-text);
  background: #fff;
  box-sizing: border-box;
  width: 100%;
}
.rc-input:focus {
  outline: none;
  border-color: var(--color-primary);
}
.rc-textarea {
  height: auto;
  padding: 8px 10px;
  resize: vertical;
  font-family: inherit;
}
.rc-form-actions {
  display: flex;
  align-items: center;
  gap: 12px;
}
.rc-form-error {
  flex: 1;
  font-size: 12px;
  color: #DF3562;
}
.rc-btn-primary {
  height: 32px;
  padding: 0 16px;
  border: none;
  border-radius: 6px;
  background: var(--color-primary);
  color: #fff;
  font-size: 13px;
  cursor: pointer;
}
.rc-btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.rc-btn-ghost {
  height: 32px;
  padding: 0 16px;
  border: 1px solid #E4E4E7;
  border-radius: 6px;
  background: #fff;
  color: var(--color-text-secondary);
  font-size: 13px;
  cursor: pointer;
}
.rc-form-hint {
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-placeholder);
}
.rc-card-foot {
  padding: 12px 20px 16px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
}

/* 统计卡 */
.rc-stats {
  display: flex;
  gap: 16px;
}
.rc-stat {
  flex: 1;
  background: var(--color-card);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 16px 18px;
}
.rc-stat-label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.rc-stat-value {
  margin-top: 6px;
  font-size: 22px;
  font-weight: 500;
  color: var(--color-text);
}

/* 三方对账行（花费 ↔ 消耗明细 ↔ 出入库） */
.rc-recon {
  margin-top: 12px;
  padding: 10px 14px;
  border-radius: 8px;
  background: var(--color-card);
  box-shadow: var(--shadow-card);
  font-size: 12px;
  color: var(--color-text-secondary);
}
.rc-recon-bad {
  color: #c0392b;
}

.rc-footnote {
  margin: 0;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
}

/* 文字色 */
.rc-strong {
  font-weight: 500;
}
.rc-secondary {
  color: var(--color-text-secondary);
}
.rc-muted {
  color: var(--color-placeholder);
}
.rc-blue {
  color: var(--color-primary);
}
.rc-purple {
  color: #6F2DC1;
}
.rc-red {
  color: #DF3562;
}
.rc-orange {
  color: #E9A845;
}
.rc-green {
  color: var(--status-done);
}
.rc-link {
  color: var(--color-primary);
  text-decoration: none;
  cursor: pointer;
}
.rc-link:hover {
  text-decoration: underline;
}
.rc-more {
  color: var(--color-text-secondary);
  text-align: center;
}

/* 审批人配置面板（仅项目负责人可见） */
.rc-apr {
  padding: 16px 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rc-apr-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.rc-apr-title {
  font-size: 14px;
  font-weight: 500;
  color: var(--color-text);
}
.rc-apr-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rc-apr-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.rc-apr-stage {
  border: 1px solid var(--color-border);
  border-radius: 8px;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  background: var(--color-fill-soft);
}
.rc-apr-stage-head {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.rc-apr-stage-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
  min-width: 64px;
}
.rc-apr-unconf {
  color: #DF3562;
  font-weight: 400;
  font-size: 12px;
}
.rc-apr-users {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.rc-apr-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 26px;
  padding: 0 4px 0 10px;
  border-radius: 13px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  font-size: 12px;
  color: var(--color-text);
}
.rc-apr-chip-x {
  border: none;
  background: transparent;
  color: var(--color-placeholder);
  font-size: 14px;
  line-height: 1;
  cursor: pointer;
  padding: 0 4px;
}
.rc-apr-chip-x:hover {
  color: #DF3562;
}
.rc-apr-empty {
  font-size: 12px;
  color: var(--color-placeholder);
}
.rc-apr-warn {
  margin: 0;
  padding-left: 18px;
  list-style: disc;
}
.rc-apr-warn li {
  font-size: 12px;
  line-height: 1.7;
  color: #DF3562;
}

/* 资源台账：原生 RepositoriesTable 的宿主容器。
   组件根节点是 `h-full`（height:100%），AG Grid 又必须拿到显式高度，所以这里必须给
   一个具体高度（资源中心的卡片是自适应高度，不能靠 flex 撑开）。
   高度算式沿用换承载前那条已验证过的值：原生 `.fixed-content-body` 原本按「原生整页」
   语境算 `calc(100vh - header - navbar)`，放到资源中心（上方已有面包屑 + 页头 + 页签）
   会算超视口 → 整页出现第二条滚动条，故按页面实际占位扣减。 */
.rc-native-repo-host {
  height: calc(100vh - var(--navbar-height, 60px) - 300px);
  min-height: 420px;
}
</style>

<!--
  非 scoped：下面这两条规则要作用在**原生组件自己渲染的 DOM** 上
  （.rc-apr-* 所在的申请表单里混着原生弹窗节点），scoped 选择器加不上 data 属性。

  ⚠ 2026-10-09：原先这里还有一条 `#eln-repositories-native .fixed-content-body { height: … }`，
  用来压住「ERB 渲染在挂载点之外的原生列表」的高度。换承载后该容器已不存在
  （原生组件现在由本页 app 渲染，高度改由 scoped 里的 `.rc-native-repo-host` 给）——
  那条规则一并删除，避免留下指向已消失 DOM 的死规则。
-->
<style>
.rc-apr-self {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--color-text);
  cursor: pointer;
}
.rc-apr-hint {
  margin-top: 4px;
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-text-secondary);
}
</style>

