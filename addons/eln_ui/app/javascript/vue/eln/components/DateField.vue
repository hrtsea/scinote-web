<template>
  <div
    class="date-field"
    :class="[`date-field--${size}`, { 'date-field--invalid': invalid, 'date-field--bare': bare }]"
    :data-e2e="dataE2e || null"
    @keydown.capture="onKeydownCapture"
    @focusout="onFocusout"
  >
    <VueDatePicker
      ref="pickerRef"
      class="date-field__picker"
      :model-value="dateObj"
      :teleport="'body'"
      :auto-apply="true"
      :clearable="clearable"
      :disabled="disabled"
      :placeholder="effectivePlaceholder"
      :week-start="0"
      :six-weeks="true"
      :no-today="true"
      :partial-flow="false"
      :month-change-on-scroll="false"
      :hide-input-icon="false"
      :enable-time-picker="false"
      :text-input="true"
      :text-input-options="textInputOptions"
      format="yyyy-MM-dd"
      :clear-button="false"
      :input-class-name="`date-field__input date-field__input--${size}`"
      menu-class-name="date-field-menu"
      @update:model-value="onPick"
      @cleared="onCleared"
    >
      <!-- 🔴 `menu-class-name="date-field-menu"` 是必需项，不是可选项：
     浮层 teleport 到 body 后已不在本组件的 DOM 子树里，若没有这个锚点 class，
     下方那段非 scoped 的浮层样式就没有可挂靠的选择器 ⇒ 浮层裸奔（无边框无阴影）。
     prop 名是 `menuClassName`（v7），kebab 写法为 menu-class-name；
     同理输入框是 `inputClassName` ⇒ input-class-name（不是 input-class）。

     前/后月箭头：沿用 ELN 自己的 AppIcon（宿主那套 /images/calendar/*.svg 是 SciNote 资产，
     会把宿主视觉带进 ELN，见 spec「视觉沿用 ELN 自己的 token」）。 -->
      <template #arrow-left>
        <AppIcon name="chevron-left" :size="16" />
      </template>
      <template #arrow-right>
        <AppIcon name="chevron-right" :size="16" />
      </template>
      <template #input-icon>
        <AppIcon name="calendar" :size="15" class="date-field__icon" />
      </template>
    </VueDatePicker>

    <!-- 自绘清空按钮：VueDatePicker 自带的 clearButton 默认只在 hover 时出现，
         而 ELN 的裸输入态（预定表单）要求常显；且 teleport 浮层里的清空位置
         在窄输入框里会挤到日期文字。故统一自绘一个受控的，常显。 -->
    <button
      v-if="clearable && modelValue && !disabled"
      type="button"
      class="date-field__clear"
      :aria-label="`清除${placeholder || '日期'}`"
      :data-e2e="dataE2e ? `${dataE2e}-clear` : null"
      @click="onCleared"
    >
      <AppIcon name="close" :size="14" />
    </button>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue/dist/vue.esm-bundler.js'
import VueDatePicker from '@vuepic/vue-datepicker'
import '@vuepic/vue-datepicker/dist/main.css'
import AppIcon from './AppIcon.vue'
import { ymd, parseYMD } from '../data/equipment'

const props = defineProps({
  /** 🔴 契约：日期字面量字符串 'YYYY-MM-DD'，空 = ''。与原生 <input type="date"> 完全一致，
   *      所以调用方的 v-model 与 data 层一行都不用改。 */
  modelValue: { type: [String, Date], default: '' },
  /** 占位提示。🔴 刻意做成"格式 + 可输入"两段信息：
   *    1) 'YYYY-MM-DD' —— 用户故事 8，输入框当场显示统一格式，
   *       用户不必关心本机浏览器用哪种日期顺序（原生的分段框做不到这点）；
   *    2) '可直接输入' —— 明确告知这是个可键入的框，不是只能点的选择器
   *       （用户故事 7：习惯键入的人不该被逼着点日历）。
   *    调用方可以覆盖（个别场景语义更贴切，如「未登记则留白」），但不传也能看到提示。 */
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  clearable: { type: Boolean, default: true },
  /** 对齐既有三种输入高度：'lg' = .field-input 36px / 'md' = .rc-date 30px / 'sm' = 无边框裸输入。 */
  size: { type: String, default: 'lg' },
  invalid: { type: Boolean, default: false },
  /** 无边框裸输入（BookingForm 的 .bf-bare 态）。 */
  bare: { type: Boolean, default: false },
  /** 无障碍标签，落到内部 input 上。v7 只给「翻月箭头」那个 button 提供 ariaLabel prop，
   *  输入框本身没有对应 prop（实测 dist：`ariaLabel` 只出现在 dp--arrow-btn-nav 上），
   *  而它渲染的 input 又不接受属性透传 ⇒ 只能自己挂。 */
  ariaLabel: { type: String, default: '' },
  dataE2e: { type: String, default: '' }
})

const emit = defineEmits(['update:modelValue', 'change'])

const pickerRef = ref(null)

// 默认占位提示（用户故事 8 + 7）。
// 🔴 为什么在组件内兜底而不是每处调用方都写一遍：
//    漏传 placeholder 时 v7 会渲染成空白框，用户既不知道格式、也不知道能打字 ——
//    那正是"像坏掉了"的观感。把默认值收在这里，新增调用方天然带提示。
//    调用方传了就用它的（个别场景语义更贴切，如 ProjectDetail 的「未登记则留白」）。
const DEFAULT_PLACEHOLDER = 'YYYY-MM-DD · 可直接输入'
const effectivePlaceholder = computed(() => props.placeholder || DEFAULT_PLACEHOLDER)

// 直接键入的交互设定（用户故事 7：不想点日历的人仍可打字）。
// 🔴 enterSubmit / tabSubmit 都**关掉**：提交由本组件的 onKeydownCapture
//    与 onFocusout 自己接管（实测 v7 内置的那条路径在本组合下不提交，
//    且会与我们的处理重复触发）。理由与实测细节见那两个函数的注释。
// selectOnFocus 关闭：聚焦时全选会让「看日期」变成「一下就删」，对只读场景不友好。
const textInputOptions = {
  enterSubmit: false,
  tabSubmit: false,
  openMenu: true,
  selectOnFocus: false
}

// ── 初值归一 ────────────────────────────────────────────────────────────
// 🔴 17 处现状初值不统一：多数是 ''，BookingForm 走 ymd(TODAY)，
//    旧 AG Grid 渲染器走 .toString().slice(0, 10)。三种形态都要正确吃下，
//    不能因形态不同抛错或显示空白。
//    判据：能被 parseYMD 解析成合法本地日期才认，否则一律当空。
function toYMDString(raw) {
  if (!raw) return ''
  if (raw instanceof Date) {
    return Number.isNaN(raw.getTime()) ? '' : ymd(raw)
  }
  let s = String(raw).trim()
  if (!s) return ''
  // 只接受完整的 YYYY-MM-DD（允许调用方传 ISO 带时间，取前 10 位）
  let head = s.slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(head)) {
    // 🔴 也接受紧凑的 8 位数字 YYYYMMDD。
    //   实测（真机）：v7 的 text-input 允许用户直接敲 `20261231`，
    //   输入框**原样接受**并显示。若这里只认带横线的形状，
    //   用户敲完按回车反而被清空 —— 比不归一更糟（看着像丢数据）。
    //   来源上不新增歧义：8 位数字按 YYYYMMDD 解读是唯一的。
    if (/^\d{8}$/.test(s)) {
      head = `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`
    } else {
      return ''
    }
  }
  const d = parseYMD(head)
  if (Number.isNaN(d.getTime())) return ''
  // 溢出防护：parseYMD('2026-02-31') 会滚到 03-03（JS 归一化），那不是用户要的日期。
  return ymd(d) === head ? head : ''
}

const currentYMD = computed(() => toYMDString(props.modelValue))

// VueDatePicker 要 Date 对象。🔴 走 ELN 已有的本地时区成对函数
//    parseYMD（new Date(y, m-1, d)，本地午夜）+ ymd（getFullYear/getMonth/getDate），
//    两者同源同口径 ⇒ 零偏移。
//    禁止 toISOString().slice(0,10)：那是 UTC，东八区每天早上减一天，且静默。
const dateObj = computed(() => (currentYMD.value ? parseYMD(currentYMD.value) : null))

function onPick(val) {
  if (!val) {
    onCleared()
    return
  }
  // 🔴 出包走 ymd（本地时区），不是 toISOString。见上方说明。
  const s = ymd(val instanceof Date ? val : parseYMD(String(val).slice(0, 10)))
  if (!s) return
  emit('update:modelValue', s)
  emit('change', s)
}

function onCleared() {
  if (!props.modelValue) return
  emit('update:modelValue', '')
  emit('change', '')
}

// 🔴🔴 直接键入的提交：**自己接管**，不依赖 VueDatePicker 的 enterSubmit。
//
// 实测（2026-10-11，v7.4.1 真机）：`textInput.enterSubmit` 在本组件的组合下
// **不提交** —— 键入 `20261231` + Enter 后输入框仍停在原串，既不归一
// 也不关闭浮层；而紧接着点日历又会把已键入内容**静默覆盖**成手点的那个日子。
// 触发条件是「同页面里另一个 DateField 已有值」（v7 内部 parse 分支与
// 浮层 openMenu 状态耦合），空面板时反而正常 —— 这种「有时好有时坏」
// 的行为不可能留给用户。
//
// 这里用 capture 阶段监听：从最外层拦截 Enter/Tab，自己读 input.value、
// 归一、emit，并 stopPropagation 让 v7 收不到这个键。
// ⚠ 必须 capture：v7 自己的 handler 挂在 input 上（冒泡阶段），
//   冒泡监听会晚一步、拦不住。
// 🔴 Tab 不拦：preventDefault 会吃掉焦点移动，破坏键盘可达性
//   （筛选面板一列日期，用户没法用 Tab 从「开始-从」走到「开始-至」）。
//   Tab 的归一交给 blur（见下方 onFocusout）—— 失焦时提交同样符合直觉，
//   且不劫持默认行为。
function onKeydownCapture(e) {
  if (e.key !== 'Enter') return
  const el = e.target
  if (!el || el.tagName !== 'INPUT') return

  const s = toYMDString(el.value)
  // 非法输入（含溢出日期）：清空并标红，不要静默留在框里装作成功。
  el.value = s
  emit('update:modelValue', s)
  emit('change', s)
  e.stopPropagation()
  e.preventDefault()
}

// 失焦提交：覆盖 Tab 离开、以及点面板别处这两种收尾。
// value 已经是 YYYY-MM-DD（v7 按 format 格式化过）时原样 emit，
// 空则当清空 —— 不会把用户半途输入的内容丢掉。
function onFocusout(e) {
  const el = e.target
  if (!el || el.tagName !== 'INPUT') return
  const s = toYMDString(el.value)
  if (s === currentYMD.value) return
  el.value = s
  emit('update:modelValue', s)
  emit('change', s)
}

defineExpose({ clear: onCleared })

// aria-label 手动挂到 v7 渲染出的 input 上（原因见 props.ariaLabel 注释）。
// 🔴 必须 afterNextTick：v7 的 input 在子组件挂载后才存在，
//    且它带自己的 data-v，拿 scoped 选择器 / ref 都够不着，只能 DOM 查询。
//    用 :deep(.date-field__input) 查询是安全的 —— class 名由 input-class-name 固定。
onMounted(() => {
  if (!props.ariaLabel) return
  const el = document.querySelector(`[data-e2e="${props.dataE2e}"] .date-field__input`)
  if (el) el.setAttribute('aria-label', props.ariaLabel)
})
</script>

<!--
  ============================================================
  输入框与浮层样式 —— 必须**非 scoped**。
  原因（实测踩到，不是想当然）：`input-class-name` 挂上去的那个元素
  是 VueDatePicker **内部渲染**的，它只带 VueDatePicker 自己的 data-v 属性，
  没有本组件的 data-v => scoped 选择器（自动加 [data-v-xxx]）永远匹配不到。
  症状曾表现为：三档 size 全渲染成同一个 38px、invalid 描边不变红、
  bare 背景不透明 —— 因为这些规则**一条都没生效**，看到的是它的默认样式。

  另外 VueDatePicker 的 .dp__input.dp__input_icon_pad 特异性高于我们的类名，
  即使作用域对了也会被盖掉 => 盒模型必须 !important（宿主
  shared/date_time_picker.vue 的 .no-border / .only-time 同款做法）。

  全局化风险控制：所有选择器都以 .date-field__input / .date-field-menu 限定，
  class 名带 date-field- 前缀，与宿主 SciNote 的选择器零重叠；
  且不新增任何全局 CSS 变量（用的都是 tokens.css 已有的）。
  ============================================================
-->
<style>
.date-field__input {
  width: 100% !important;
  box-sizing: border-box;
  border: 1px solid var(--color-border) !important;
  border-radius: 8px;
  background: var(--color-card) !important;
  color: var(--color-text);
  font-family: inherit;
  outline: none;
  box-shadow: none !important;
  transition: border-color 0.12s;
}

/*  🔴 padding 必须四边分别写，不能用简写。
     VueDatePicker's .dp__input_icon_pad 类名暗示它给 input 加了「图标位」的 padding
     （图标 slot 在左侧），而清空按钮是我们自绘、绝对定位在右侧。
     若用 `padding: 0 12px` 简写，会把这两侧的 padding 一起重置掉
     ⇒ 实测症状：日历图标压住占位文字（「选empty」变成图标+「empty」叠在一起），
       清空按钮也会压住日期数字。 */
.date-field__input--lg {
  height: 36px !important;
  padding-left: 30px !important;  /* 日历图标 15px + 间隙 */
  padding-right: 32px !important; /* 自绘清空按钮 20px + 间隙 */
  font-size: 13px;
}

.date-field__input--md {
  height: 30px !important;
  padding-left: 28px !important;
  padding-right: 30px !important;
  border-radius: 6px;
  font-size: 12px;
}

/* 裸输入（预定表单，对应既有 .bf-bare：无边框、透明底） */
.date-field__input--sm {
  height: 28px !important;
  padding-left: 24px !important;
  padding-right: 26px !important;
  border-color: transparent !important;
  background: transparent !important;
  font-size: 13px;
  font-family: var(--font-en);
}

.date-field__input:focus {
  border-color: var(--color-primary) !important;
}

.date-field__input::placeholder {
  color: var(--color-placeholder) !important;
}

/* 裸输入态：聚焦时不画边框（预订表单要的是「像文本」的手感） */
.date-field--bare .date-field__input:focus {
  border-color: transparent !important;
}

/* 区间反了等错误态：视觉告警，不阻断提交 */
.date-field--invalid .date-field__input {
  border-color: var(--color-danger) !important;
  background: var(--color-danger-bg) !important;
}
</style>

<!--
  清空按钮留在 scoped 段（它由本组件模板直接渲染，带本组件 data-v，
  scoped 生效且能隔离）。
-->
<style scoped>
.date-field {
  position: relative;
  display: block;
  width: 100%;
}

.date-field__picker {
  display: block;
  width: 100%;
}

.date-field__clear {
  position: absolute;
  top: 50%;
  right: 6px;
  transform: translateY(-50%);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  padding: 0;
  border: none;
  border-radius: 50%;
  background: var(--color-fill-soft);
  color: var(--color-text-secondary);
  line-height: 0;
  /* 必须高于 input：VueDatePicker 的 .dp__input 自带定位上下文，
     低 z-index 会被压在下面（点不到）。 */
  z-index: 3;
  cursor: pointer;
}

.date-field__clear:hover {
  background: var(--color-border);
  color: var(--color-text);
}
</style>

<!--
  浮层（菜单）样式 —— 非 scoped，原因同上一段：teleport 到 body 后
  DOM 已脱离本组件作用域。全局化风险由 .date-field-menu 前缀控制，
  该前缀与宿主 SciNote 的选择器零重叠。
-->
<style>
.date-field-menu.dp__menu {
  z-index: 2147483000; /* 高于 AG Grid 弹层（AG Grid 用 z-index 1000+ 档），
                          也高于 ELN 自己的 overlay 背板 */
  border: 1px solid var(--color-border);
  border-radius: 10px;
  background: var(--color-card);
  box-shadow: var(--shadow-pop);
  font-family: var(--font-sans);
  color: var(--color-text);
}

/* 输入框既承担「点开日历」的点击面，也承担直接键入（text-input 已开，
   format 固定 yyyy-MM-dd）⇒ 光标样式用 text 而非 pointer。 */
.date-field-menu .dp__main .dp__input_wrap .dp__input {
  cursor: text;
}

.date-field-menu .dp__month_view {
  border: none;
}

.date-field-menu .dp__month_year_select {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
}

.date-field-menu .dp__weekday {
  font-size: 12px;
  color: var(--color-text-secondary);
}

.date-field-menu .dp__day {
  font-size: 12px;
  border-radius: 6px;
  color: var(--color-text);
}

.date-field-menu .dp__day.dp__selected_day {
  background: var(--color-primary);
  color: #fff;
}

.date-field-menu .dp__active_button,
.date-field-menu .dp__today {
  border-radius: 6px;
}

.date-field-menu .dp__arrow_button {
  color: var(--color-text-secondary);
}
</style>