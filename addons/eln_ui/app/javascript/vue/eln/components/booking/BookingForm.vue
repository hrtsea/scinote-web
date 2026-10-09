<template>
  <!-- 新建预定表单（画布 70:165 字段网格 / 70:192 按钮行）
       卡头「新建预定 + 选中设备」由父级 EquipmentBooking.vue 渲染（对应 70:162） -->
  <div class="booking-form">
    <div class="bf-cols">
      <!-- 左列 70:166（gap 12） -->
      <div class="bf-col">
        <!-- 字段-预定日期 70:167（标签 + 输入，gap 4） -->
        <div class="bf-field">
          <label class="bf-label">预定日期</label>
          <div class="bf-affix">
            <input v-model="form.date" type="date" class="bf-bare" />
            <span class="bf-suffix">· 周{{ weekdayOf(form.date) }}</span>
          </div>
        </div>

        <!-- 字段-时间段 70:171（时间行 gap 12，输入 h36） -->
        <div class="bf-field">
          <label class="bf-label">时间段</label>
          <div class="bf-time-row">
            <input v-model="form.start" type="time" class="bf-input" />
            <span class="bf-tilde">–</span>
            <input v-model="form.end" type="time" class="bf-input" />
          </div>
        </div>

        <!-- 字段-关联实验 70:178 -->
        <div class="bf-field">
          <label class="bf-label">关联实验</label>
          <select v-model="form.relatedExp" class="bf-input">
            <option v-for="e in relatedExperiments" :key="e.id" :value="e.id">{{ e.id }} · {{ e.name }}</option>
          </select>
        </div>
      </div>

      <!-- 右列 70:183（gap 12） -->
      <div class="bf-col">
        <!-- 字段-用途说明 70:184（多行输入 h66） -->
        <div class="bf-field">
          <label class="bf-label">用途说明</label>
          <textarea
            v-model="form.purpose"
            rows="3"
            class="bf-input bf-textarea"
            placeholder="如：冲击强度测试、混料均匀性验证"
          ></textarea>
        </div>

        <!-- 字段-审批人 70:188（只读框 h36 / #FAFAFA） -->
        <div class="bf-field">
          <label class="bf-label">审批人</label>
          <div class="bf-readonly-box">{{ approver }}（设备负责人）· 提交后自动通知</div>
        </div>
      </div>
    </div>

    <div v-if="error" class="bf-error">{{ error }}</div>

    <!-- 按钮行 70:192（gap 8：提交预定申请 + 取消 + 提示文案） -->
    <div class="bf-actions">
      <button class="eln-btn-primary" @click="submit">提交预定申请</button>
      <button class="eln-btn-ghost" @click="reset">取消</button>
      <span class="bf-note">预计时长 2 小时 · 与现有预定无冲突 · 提交后通知 {{ approver }} 审批</span>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue/dist/vue.esm-bundler.js'
import { relatedExperiments, DEFAULT_APPROVER, ymd, TODAY, WEEKDAY_CN } from '../../data/equipment.js'

const emit = defineEmits(['submit'])

const approver = DEFAULT_APPROVER
const error = ref('')

const form = reactive({
  relatedExp: relatedExperiments[0].id,
  date: ymd(TODAY),
  start: '16:00',
  end: '18:00',
  purpose: '拉伸强度与断裂伸长率测试（Dow ADH-6066 三批试样）'
})

// 画布 70:170「2026-09-29 · 周二」
function weekdayOf(s) {
  const d = new Date(s + 'T00:00:00')
  if (isNaN(d.getTime())) return ''
  return WEEKDAY_CN[(d.getDay() + 6) % 7]
}

function submit() {
  if (!form.start || !form.end) {
    error.value = '请填写完整的起止时间'
    return
  }
  if (form.start >= form.end) {
    error.value = '结束时间须晚于开始时间'
    return
  }
  error.value = ''
  emit('submit', {
    deviceId: null, // 由父级注入当前设备
    date: form.date,
    start: form.start,
    end: form.end,
    relatedExp: form.relatedExp,
    purpose: form.purpose || '新预定'
  })
}

function reset() {
  error.value = ''
  form.relatedExp = relatedExperiments[0].id
  form.date = ymd(TODAY)
  form.start = '16:00'
  form.end = '18:00'
  form.purpose = ''
}
</script>

<style scoped>
.booking-form {
  display: flex;
  flex-direction: column;
  gap: 14px;
}
/* 字段网格 70:165（两列 gap 24） */
.bf-cols {
  display: flex;
  gap: 24px;
  align-items: flex-start;
}
.bf-col {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.bf-field {
  display: flex;
  flex-direction: column;
  gap: 4px; /* 画布 70:167 字段 gap 4 */
}
.bf-label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.bf-input,
.bf-affix {
  height: 36px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  background: var(--color-card);
  font-size: 13px;
  color: var(--color-text);
}
.bf-input {
  padding: 0 10px;
  font-family: var(--font-sans);
  outline: none;
  transition: border-color 0.15s ease;
}
.bf-input:focus {
  border-color: var(--color-primary);
}
.bf-textarea {
  height: 66px; /* 画布 70:186 */
  padding: 8px 10px;
  resize: vertical;
  line-height: 1.5;
}
/* 日期框（含「· 周X」后缀，画布 70:170） */
.bf-affix {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 10px;
}
.bf-bare {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  background: transparent;
  font-size: 13px;
  font-family: var(--font-en);
  color: var(--color-text);
}
.bf-suffix {
  flex-shrink: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.bf-time-row {
  display: flex;
  align-items: center;
  gap: 12px; /* 画布 70:173 */
}
.bf-time-row .bf-input {
  flex: 1;
  min-width: 0;
}
.bf-tilde {
  color: var(--color-text-secondary);
}
/* 审批人只读框 70:190（h36 / pad 0 10 / r8 / #FAFAFA） */
.bf-readonly-box {
  height: 36px;
  display: flex;
  align-items: center;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  background: var(--color-page-bg);
  font-size: 13px;
  color: var(--color-text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.bf-error {
  font-size: 12px;
  color: var(--color-danger);
}
/* 按钮行 70:192（gap 8） */
.bf-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.bf-note {
  flex: 1;
  min-width: 0;
  font-size: 12px;
  color: var(--color-placeholder);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
