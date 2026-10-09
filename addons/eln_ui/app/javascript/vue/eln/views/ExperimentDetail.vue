<template>
  <!-- 实验详情（画布 4:69 / 4:525）：面包屑 + 页头 + 实验管理区（竖向导航212 + 内容面板） -->
  <div class="exp-detail">
    <div class="breadcrumb">
      <router-link to="/eln_project_list" class="crumb-link">项目列表</router-link>
      <span class="crumb-sep">/</span>
      <router-link :to="projectDetailUrl" class="crumb-link">{{ expProjectName }}</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">{{ expTitle }}</span>
    </div>

    <!-- 页头 4:527 -->
    <div class="exp-head">
      <div class="head-text">
        <div class="head-row">
          <h1 class="head-title">{{ expTitle }}</h1>
          <span class="eln-badge eln-badge-green">{{ expStatusText }}</span>
        </div>
        <p class="head-sub">
          实验 Experiment 层级 · 状态由 started_at / done_at 推导为三态，不因子任务完成自动推进（SCN-EXP-DETAIL-2/3）
        </p>
      </div>
      <button class="eln-btn-primary">编辑实验信息</button>
    </div>

    <!-- 实验管理区 4:581 -->
    <div class="em-card">
      <!-- 竖向导航 212（画布 4:582 仅 2 项，无分组标题） -->
      <nav class="em-nav">
        <button
          v-for="n in expNav"
          :key="n.key"
          class="em-nav-item"
          :class="{ active: activeNav === n.key }"
          @click="activeNav = n.key"
        >
          {{ n.label }}
        </button>
      </nav>
      <div class="em-divider"></div>

      <!-- 内容面板 4:593 -->
      <div class="em-content">
        <!-- 实验概况：子页签栏 4 项（画布 70:1） -->
        <template v-if="activeNav === 'overview'">
          <div class="sub-tabs">
            <button
              v-for="t in expSubTabs"
              :key="t.key"
              class="sub-tab"
              :class="{ active: activeSub === t.key }"
              @click="activeSub = t.key"
            >
              {{ t.label }}
            </button>
          </div>
          <div class="sub-divider"></div>

          <!-- 子页签 · 实验设计与配方优化（画布 70:11，唯一有画布真值的面板） -->
          <div v-if="activeSub === 'design'" class="pane">
            <div class="pane-head">
              <div class="pane-head-text">
                <div class="pane-title">实验设计与配方优化</div>
                <div class="pane-sub">
                  挂实验级（DEC-009）· 项目负责人与小组组长可完整操作，组员不可访问（DEC-001）
                </div>
              </div>
              <span class="eln-badge eln-badge-orange">云版 · 消耗 Token</span>
            </div>

            <!-- 场景切换 4:600 -->
            <div class="scene-switch">
              <button
                class="scene"
                :class="{ active: scene === 'A' }"
                @click="scene = 'A'"
              >
                场景 A · 无历史数据（DOE）
              </button>
              <button
                class="scene"
                :class="{ active: scene === 'B' }"
                @click="scene = 'B'"
              >
                场景 B · 已有历史数据（贝叶斯优化）
              </button>
            </div>

            <!-- DV 设计变量表 4:605 / 4:614 / 4:623 -->
            <div class="var-head">
              <span class="col-check"><span class="checkbox"></span></span>
              <span class="col-var">DV 设计变量</span>
              <span class="col-type">类型</span>
              <span class="col-range">取值范围</span>
              <span class="col-limit">约束</span>
            </div>
            <div v-for="v in expDesignVars" :key="v.name" class="var-row">
              <span class="col-check"><span class="checkbox"></span></span>
              <span class="col-var">{{ v.name }}</span>
              <span class="col-type">{{ v.type }}</span>
              <span class="col-range num">{{ v.range }}</span>
              <span class="col-limit">{{ v.constraint }}</span>
            </div>
            <!-- 显式留白：真机该实验没配 DOE 变量时，空表下面给一句说明。
                 原型独立跑时 expDesignVars 是 mock 的 3 行，不会走到这里（视觉零变化）。 -->
            <p class="pane-empty" v-if="!expDesignVars.length">
              ⓘ 该实验未配置设计变量 —— 原生无 DOE 模块，变量表为二开（eln_ui_design_variables）；
              空表是合法状态，不是取数失败。
            </p>

            <!-- 操作行 4:632 -->
            <div class="action-row">
              <button class="eln-btn-ghost">重新计算贝叶斯优化</button>
              <button class="eln-btn-primary">
                <AppIcon name="plus" :size="16" />一键生成验证任务
              </button>
              <span class="action-hint">
                生成在当前实验下 · 产出不自动改写项目指标状态（SCN-PM-EXP-8）
              </span>
            </div>
          </div>

          <!-- 以下三个面板画布中 visible:false，按实验主数据补全（显式标注来源） -->
          <div v-else-if="activeSub === 'info'" class="pane">
            <div class="pane-head">
              <div class="pane-head-text">
                <div class="pane-title">实验信息</div>
                <div class="pane-sub">实验 Experiment 主数据 · 与项目详情「实验列表」同源</div>
              </div>
              <button class="eln-btn-ghost sm">编辑</button>
            </div>
            <div class="field-grid">
              <div class="f-item"><span class="f-label">实验编号</span><span class="f-value num">{{ infoCode }}</span></div>
              <div class="f-item"><span class="f-label">实验名称</span><span class="f-value">{{ infoName }}</span></div>
              <div class="f-item">
                <span class="f-label">状态</span>
                <span class="f-value">
                  <span class="status-dot" :style="{ background: infoStateColor }"></span>{{ infoState }}
                </span>
              </div>
              <div class="f-item"><span class="f-label">所属项目</span><span class="f-value">{{ infoProject }}</span></div>
              <div class="f-item"><span class="f-label">实验负责人</span><span class="f-value">{{ infoOwner }}</span></div>
              <div class="f-item"><span class="f-label">计划完成</span><span class="f-value num">{{ infoDue }}</span></div>
              <div class="f-item"><span class="f-label">任务进度</span><span class="f-value num">{{ infoProgress }}</span></div>
            </div>
            <p class="pane-foot">
              ⓘ 画布 4:69 该面板为 hidden 态，字段按「项目基础信息」同源口径补全，未改动任何画布口径（DEC-009）。
            </p>
            <p class="pane-foot">
              ⓘ 真值口径：编号取原生 Experiment#code（EX+主键）、状态由 started_at / done_at 推导、
              负责人取实验指派人（无则创建者）、计划完成取 due_date、任务进度 = 已完成任务/总任务。
            </p>
          </div>

          <div v-else-if="activeSub === 'purpose'" class="pane">
            <div class="pane-head">
              <div class="pane-head-text">
                <div class="pane-title">实验目的</div>
                <div class="pane-sub">承接项目描述中的量化目标，用于判定实验达标口径</div>
              </div>
            </div>
            <!-- 正文：宿主注入真值；注入不到（原型独立跑）落回画布演示文案 -->
            <p class="pane-body">{{ expPurpose }}</p>
            <p class="pane-empty" v-if="!expPurpose">
              ⓘ 未填写实验目的 —— 原生无此字段，真值来自实验档案（eln_ui_experiment_profiles）；
              没有档案时这里必须留白，不能拿演示文案顶。
            </p>
            <p class="pane-foot">
              ⓘ 画布 4:69 该面板为 hidden 态；真值优先取实验档案 purpose，
              退回原生 experiments.description（富文本压成纯文本）。
            </p>
          </div>

          <div v-else class="pane">
            <div class="pane-head">
              <div class="pane-head-text">
                <div class="pane-title">实验方案与方法</div>
                <div class="pane-sub">执行计划取自任务详情「执行计划」（画布 4:747）</div>
              </div>
            </div>
            <!-- 步骤：宿主注入真值，按行拆；注入不到落回画布演示文案 -->
            <ol class="plan-list">
              <li v-for="(s, i) in methodSteps" :key="i">{{ s }}</li>
            </ol>
            <p class="pane-empty" v-if="!methodSteps.length">
              ⓘ 未填写实验方案 —— 原生无承载面（experiments 没有步骤列），
              真值来自实验档案 method；没有档案就留白。
            </p>
            <p class="pane-foot">
              ⓘ 画布 4:69 该面板为 hidden 态；真值取实验档案 method（多行，按行渲染为步骤列表）。
            </p>
          </div>
        </template>

        <!-- 实验任务面板（画布 4:537 visible:false） -->
        <div v-else class="pane pane-plain">
          <div class="pane-head">
            <div class="pane-head-text">
              <div class="pane-title">实验任务</div>
              <div class="pane-sub">MyModule 任务列表 · 点击名称进入任务详情</div>
            </div>
            <button class="eln-btn-primary sm"><AppIcon name="plus" :size="16" />新建任务</button>
          </div>
          <table class="eln-table">
            <thead>
              <tr>
                <th class="eln-th" style="width: 40px"><span class="checkbox"></span></th>
                <th class="eln-th">任务名称</th>
                <th class="eln-th" style="width: 110px">状态</th>
                <th class="eln-th" style="width: 130px">指派组员</th>
                <th class="eln-th" style="width: 110px">截止日期</th>
                <th class="eln-th" style="width: 56px">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="t in tasks" :key="t.id">
                <td class="eln-td"><span class="checkbox"></span></td>
                <td class="eln-td">
                  <router-link :to="drillTo(t, 'task')" class="task-link">{{ t.name }}</router-link>
                </td>
                <td class="eln-td">{{ taskStatusLabel[t.status] }}</td>
                <td class="eln-td">
                  <span class="member-cell">
                    <span class="avatar" :style="avatarStyle(t.owner.color)">{{ t.owner.initial }}</span>
                    {{ t.owner.name }}
                  </span>
                </td>
                <td class="eln-td num">{{ t.due }}</td>
                <td class="eln-td"><button class="row-more"><AppIcon name="more" :size="16" /></button></td>
              </tr>
            </tbody>
          </table>
          <p class="pane-foot">
            ⓘ 画布 4:537 该面板为 hidden 态；列结构沿用项目详情「实验列表」同款表格口径。
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue/dist/vue.esm-bundler.js'
import AppIcon from '../components/AppIcon.vue'
// ⚠ drillTo 必须 import（2026-10-05 修一个把整页打挂的错）：
//   任务名下钻改成 drillTo(t,'task') 后忘了引入 → 模板求值时抛
//   「drillTo is not a function」→ **整个 ExperimentDetail 组件渲染失败**，
//   真机表现是页面只剩宿主导航条、body 29 字符、0 个任务行，
//   很容易误判成"下钻没数据"。凡是模板里用到的新函数，先问 import 了吗。
import { drillTo } from '../utils/drill'
// ⚠ 默认子页签从 store/ui 取，而不是写死 'design'：
//   原型独立跑（npm run dev）时 ui.expDefaultSub 是 undefined → 仍是 'design'，
//   演示态一行没变；挂进 SciNote 后宿主可注入 'tasks' 让首屏就是真任务列表。
//   为什么要动这一行：原型的 activeSub 初值写死 'design'（画布 70:8 的选中态是
//   演示值），组件源码里没有任何入口能改它。而 PRD §7.7 明确「tasks 任务列表
//   默认选中」，原生 my_modules#index 本来也是任务列表。真机默认的 design 面板
//   是**原型硬编码的假文案**（DOE 表 + 执行步骤），首屏给假数据不行。
//   （对齐 PRD 的默认页签，已记 OPEN-6；只改初值来源，不改画布选中态。）
import { ui } from '../store/ui'
import {
  expNav,
  expSubTabs,
  expDesignVars,
  tasks,
  taskStatusLabel,
  avatarPalette
} from '../data/mock'

// ⚠ 默认**左栏**页签才是关键：任务表格在 activeNav==='tasks' 那一条分支里
//   （模板第 179 行 <div v-else class="pane pane-plain">），
//   activeSub 只管「实验概况」内部显示哪个 Pane。
//   原型初值写死 'overview' + activeSub 'design' → 首屏是「实验方案与方法」那块
//   **原型硬编码的假文案**（5 条执行步骤）；PRD §7.7 却要求 tasks 默认选中
//   （原生 my_modules#index 本来就是任务列表）。所以宿主注入 expDefaultNav='tasks'。
// ⚠ 标题 / 面包屑项目名 / 状态徽标原本是**原型写死的演示文案**
//   （EX1 · 硅胶配方与固化体系筛选 / 150°C 蒸汽环境金属粘接用高温硅胶研究 / 进行中）。
//   真机上挂的是别的实验（生产库那台是真实验叫 Microbiological sampling_QA），
//   原样渲染等于在真实页面里顶着别人的项目名 —— 所以这三个值走宿主注入，
//   注入不到时（原型独立跑）自动落回原型的演示文案，演示态一行没变。
const expTitle = ui.expTitle || 'EX1 · 硅胶配方与固化体系筛选'
const expProjectName = ui.expProjectName || '150°C 蒸汽环境金属粘接用高温硅胶研究'
// 面包屑「项目名」的下钻地址：宿主注入真实项目详情页；没注入（原型独立跑）落回
// 原型路径 /projects/<id>。**不用演示 id 兜底** —— 那是画布假值，真机上点了必404。
const projectDetailUrl = ui.projectDetailUrl || `/projects/${ui.expProjectId || ''}`
const expStatusText = ui.expStatusText || '进行中'

// ⚠「实验信息」面板 7 格原本也是**原型写死的假值**
//   （EX1 / 硅胶配方与固化体系筛选 / 张负责人 / 2026-09-30 / 1/3 任务 …）。
//   这是整页最后一块假数据 —— 现在页面上写的实验叫别的名字、负责人是别人，
//   信息面板却还顶着「硅胶配方」和「张负责人」，等于同一屏里自相矛盾。
//   走宿主注入；注入不到（原型独立跑 dev）落回原型的演示值，演示态一行没变。
// ⚠「实验目的 / 实验方案与方法」两块正文原本也是**原型写死的演示文案**
//   （Dow ADH-6066 / 拉伸剪切强度 ≥ 8.0 MPa / 5 条假步骤）。真值来自实验档案
//   （eln_ui_experiment_profiles.purpose / method，原生无承载面）。
//   宿主注入不到时落回演示文案，保持原型独立跑（npm run dev）的演示态一行没变；
//   真机注入后必然是档案里的真值 —— 验收脚本会拦「页面上还留着演示文案」。
// ⚠ const 有 TDZ：这两个「注入不到时的兜底文案」必须先于 expPurpose/expMethod 声明，
//   写成 `const expPurpose = ui.expPurpose || EX_PURPOSE_DEMO` 在上面、常量在下面会
//   直接抛 ReferenceError（组件静默不挂载，且这类错在构建期完全看不出来）。
const EX_PURPOSE_DEMO =
  '在 150°C 蒸汽环境下，筛选耐高温加成型硅胶（首选 Dow ADH-6066）的基料与固化剂配比窗口，' +
  '使 500h 蒸汽老化后拉伸剪切强度 ≥ 8.0 MPa、内聚破坏占比 ≥ 80%。'
const EX_METHOD_DEMO = [
  '基材打磨除油（6061 铝 · 240 目砂纸 + 丙酮）',
  '底涂剂涂覆并固化（150°C × 30 min）',
  '硅胶粘接与固化剂配比变量控制',
  '150°C 蒸汽老化 500h',
  '拉伸剪切强度测试（n=3）'
].join('\n')

const expPurpose = ui.expPurpose || EX_PURPOSE_DEMO
const expMethod = ui.expMethod || EX_METHOD_DEMO
// 真值是多行文本：按行拆成步骤（档案里 method 一列存全文，行 = 一步）
const methodSteps = expMethod.split('\n').map((s) => s.trim()).filter(Boolean)

const info = ui.expInfo || {}
const infoCode = info.code || 'EX1'
const infoName = info.name || '硅胶配方与固化体系筛选'
const infoState = info.state || '进行中'
const infoStateColor = info.stateColor || 'var(--status-active)'
const infoProject = info.project || '150°C 蒸汽环境金属粘接用高温硅胶研究'
const infoOwner = info.owner || '张负责人'
const infoDue = info.due || '2026-09-30'
const infoProgress = info.progress || '1/3 任务'

const activeNav = ref(ui.expDefaultNav || 'overview')
const activeSub = ref(ui.expDefaultSub || 'design') // 默认 design（画布 70:8）；宿主可注入覆盖
const scene = ref('B') // 画布 4:603 选中态 = 场景 B

function avatarStyle(color) {
  const c = avatarPalette[color] || avatarPalette.blue
  return { background: c.bg, color: c.fg }
}
</script>

<style scoped>
.exp-detail {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px;
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

/* 页头 4:527 */
.exp-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.head-text {
  display: flex;
  flex-direction: column;
  gap: 6px;
  flex: 1;
  min-width: 0;
}
.head-row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.head-title {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.head-sub {
  margin: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}

/* 实验管理区 4:581 */
.em-card {
  display: flex;
  align-items: stretch;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  overflow: hidden;
}
.em-nav {
  width: 212px;
  flex-shrink: 0;
  padding: 12px 10px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.em-nav-item {
  height: 38px;
  padding: 0 10px;
  border: none;
  background: transparent;
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-text-menu);
  text-align: left;
  transition: background 0.12s ease, color 0.12s ease;
}
.em-nav-item:hover {
  background: var(--color-fill-soft);
}
.em-nav-item.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}
.em-divider {
  width: 1px;
  background: var(--color-border);
}
.em-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

/* 子页签栏 70:1 高44 pad 4/16 */
.sub-tabs {
  display: flex;
  gap: 4px;
  padding: 6px 16px;
  height: 44px;
  align-items: center;
}
.sub-tab {
  height: 32px;
  padding: 0 12px;
  border: none;
  background: transparent;
  border-radius: 6px;
  font-size: 13px;
  color: var(--color-text-menu);
  transition: background 0.15s ease, color 0.15s ease;
}
.sub-tab:hover {
  background: var(--color-fill-soft);
}
.sub-tab.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}
.sub-divider {
  height: 1px;
  background: #F5F5F5;
}

/* 页签内容 70:11 pad20 gap14 */
.pane {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.pane-plain {
  gap: 12px;
}
/* 画布表格栅格（tokens.css .eln-th/.eln-td）：表格顶到 pane 边缘，20px 内缩由单元格自带。
   pane 内还有非表格子块（卡头 / 执行计划列表 / 卡尾），故以负边距抵消 pane 的 20px 内边距，
   使卡头标题与表格首列文字对齐于同一条 20px 基线。 */
.pane .eln-table {
  margin: 0 -20px;
  width: calc(100% + 40px);
}
.pane-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.pane-head-text {
  display: flex;
  flex-direction: column;
  gap: 3px;
  flex: 1;
  min-width: 0;
}
.pane-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.pane-sub {
  font-size: 11px;
  color: var(--color-placeholder);
}
.pane-body {
  margin: 0;
  font-size: 13px;
  line-height: 1.7;
  color: var(--color-text-menu);
}
.plan-list {
  margin: 0;
  padding-left: 20px;
  font-size: 13px;
  line-height: 1.9;
  color: var(--color-text-menu);
}
.pane-foot {
  margin: 0;
  font-size: 11px;
  line-height: 1.6;
  color: var(--color-placeholder);
}
/* 「没数据」时的显式留白说明（真机该实验没档案 / 没配 DOE 变量时出现） */
.pane-empty {
  margin: 0;
  padding: 10px 12px;
  border: 1px dashed var(--color-border);
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.6;
  color: var(--color-placeholder);
}

/* 场景切换 4:600 */
.scene-switch {
  display: flex;
  gap: 4px;
  padding: 4px;
  height: 40px;
  background: var(--color-fill-soft);
  border-radius: 10px;
}
.scene {
  flex: 1;
  border: none;
  background: transparent;
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-subtle-text);
  transition: background 0.15s ease, color 0.15s ease;
}
.scene.active {
  background: var(--color-card);
  color: var(--color-text);
  font-weight: 500;
}

/* DV 变量表 4:605 / 4:614 */
.var-head,
.var-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 10px;
  border-radius: var(--radius-table-header);
}
.var-head {
  height: 40px;
  background: var(--color-table-header);
}
.var-row {
  height: 48px;
}
.col-check {
  width: 40px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
}
.col-var {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.col-type {
  width: 80px;
  flex-shrink: 0;
}
.col-range {
  width: 140px;
  flex-shrink: 0;
}
.col-limit {
  width: 110px;
  flex-shrink: 0;
}
.var-head .col-var,
.var-head .col-type,
.var-head .col-range,
.var-head .col-limit {
  font-size: 11px;
  font-weight: 500;
  color: var(--color-text-secondary);
}
.var-row .col-var {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.var-row .col-type,
.var-row .col-limit {
  font-size: 12px;
  color: var(--color-subtle-text);
}
.var-row .col-range {
  font-size: 12px;
  color: var(--color-subtle-text);
}

/* 操作行 4:632 */
.action-row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.action-hint {
  font-size: 11px;
  color: var(--color-placeholder);
  flex: 1;
  min-width: 180px;
}

/* 实验信息字段网格 */
.field-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px 32px;
}
.f-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.f-label {
  font-size: 11px;
  color: var(--color-placeholder);
}
.f-value {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.num {
  font-family: var(--font-en);
  font-variant-numeric: tabular-nums;
}

/* 表格（表头 40 / 数据行 48 与列内边距见 tokens.css 画布栅格） */
.eln-table {
  border-collapse: collapse;
}
.eln-table .eln-td {
  border-bottom: 1px solid var(--color-border);
}
.eln-table tr:last-child .eln-td {
  border-bottom: none;
}
.task-link {
  color: var(--color-text);
  font-weight: 500;
}
.task-link:hover {
  color: var(--color-primary);
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
.row-more {
  width: 28px;
  height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  border-radius: 6px;
  color: var(--color-placeholder);
}
.row-more:hover {
  background: var(--color-fill-soft);
  color: var(--color-text);
}
.sm {
  height: 32px;
  padding: 0 12px;
  font-size: 12px;
}
</style>
