<template>
  <div
    class="date-field"
    :class="[`date-field--${size}`, { 'date-field--invalid': invalid, 'date-field--bare': bare }]"
    :data-e2e="dataE2e || null"
  >
    <VueDatePicker
      ref="pickerRef"
      class="date-field__picker"
      :model-value="dateObj"
      :teleport="'body'"
      :auto-apply="true"
      :clearable="clearable"
      :disabled="disabled"
      :placeholder="placeholder"
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
import { computed, ref } from 'vue/dist/vue.esm-bundler.js'
import VueDatePicker from '@vuepic/vue-datepicker'
import '@vuepic/vue-datepicker/dist/main.css'
import AppIcon from './AppIcon.vue'
import { ymd, parseYMD } from '../data/equipment'

const props = defineProps({
  /** 🔴 契约：日期字面量字符串 'YYYY-MM-DD'，空 = ''。与原生 <input type="date"> 完全一致，
   *      所以调用方的 v-model 与 data 层一行都不用改。 */
  modelValue: { type: [String, Date], default: '' },
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  clearable: { type: Boolean, default: true },
  /** 对齐既有三种输入高度：'lg' = .field-input 36px / 'md' = .rc-date 30px / 'sm' = 无边框裸输入。 */
  size: { type: String, default: 'lg' },
  invalid: { type: Boolean, default: false },
  /** 无边框裸输入（BookingForm 的 .bf-bare 态）。 */
  bare: { type: Boolean, default: false },
  dataE2e: { type: String, default: '' }
})

const emit = defineEmits(['update:modelValue', 'change'])

const pickerRef = ref(null)

// 直接键入的交互设定（用户故事 7：不想点日历的人仍可打字）。
// tabSubmit / enterSubmit 都开：回车与 Tab 都能确认，且确认即提交（配合 auto-apply）。
// selectOnFocus 关闭：聚焦时全选会让「看日期」变成「一下就删」，对只读场景不友好。
const textInputOptions = {
  enterSubmit: true,
  tabSubmit: true,
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
  const s = String(raw).trim()
  if (!s) return ''
  // 只接受完整的 YYYY-MM-DD（允许调用方传 ISO 带时间，取前 10 位）
  const head = s.slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(head)) return ''
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

defineExpose({ clear: onCleared })
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