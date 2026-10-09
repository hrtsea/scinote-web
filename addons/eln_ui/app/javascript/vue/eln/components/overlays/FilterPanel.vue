<template>
  <!-- 筛选面板（画布 40:122）：400 宽白底边框圆角12
       真机条件键名与原生 Lists::ProjectsService#filter_project_records 一一对应，
       所以「这里筛出来的」==「原生项目页筛出来的」，不另造一套口径。 -->
  <div v-if="ui.filterOpen" class="overlay-backdrop" @click.self="closeFilter">
    <div class="filter-panel eln-card">
      <div class="panel-header">
        <span class="panel-title">筛选</span>
        <button class="close-btn" @click="closeFilter"><AppIcon name="close" :size="16" /></button>
      </div>
      <div class="panel-body">
        <div class="field">
          <label class="field-label">包含文本</label>
          <input v-model="ui.filters.query" class="field-input" placeholder="输入搜索词…" data-e2e="fp-query" />
        </div>
        <div class="field">
          <label class="field-label">开始日期</label>
          <div class="range">
            <input v-model="ui.filters.start_date_from" type="date" class="field-input" data-e2e="fp-start-from" />
            <span class="range-sep">至</span>
            <input v-model="ui.filters.start_date_to" type="date" class="field-input" />
          </div>
        </div>
        <div class="field">
          <label class="field-label">截止日期</label>
          <div class="range">
            <input v-model="ui.filters.due_date_from" type="date" class="field-input" data-e2e="fp-due-from" />
            <span class="range-sep">至</span>
            <input v-model="ui.filters.due_date_to" type="date" class="field-input" />
          </div>
        </div>
        <div v-if="ui.viewMode === 'archived'" class="field">
          <label class="field-label">归档日期</label>
          <div class="range">
            <input v-model="ui.filters.archived_on_from" type="date" class="field-input" />
            <span class="range-sep">至</span>
            <input v-model="ui.filters.archived_on_to" type="date" class="field-input" />
          </div>
        </div>
        <div class="field">
          <label class="field-label">成员</label>
          <select v-model="ui.filters.members" multiple size="4" class="field-input multi" data-e2e="fp-members">
            <option v-for="m in memberOptions" :key="m.id" :value="m.id">{{ m.name }}</option>
          </select>
        </div>
        <div class="field">
          <label class="field-label">项目负责人</label>
          <select v-model="ui.filters.headOfProject" class="field-input" data-e2e="fp-head">
            <option value="">全部负责人</option>
            <option v-for="m in headOptions" :key="m.id" :value="m.id">{{ m.name }}</option>
          </select>
        </div>
        <div class="field">
          <label class="field-label">状态</label>
          <div class="status-chips">
            <button
              v-for="s in statusOptions"
              :key="s.value"
              class="status-chip"
              :class="{ on: ui.filters.statuses.includes(s.value) }"
              :data-e2e="`fp-status-${s.value}`"
              @click="toggleStatus(s.value)"
            >
              <span class="status-dot" :style="{ background: s.color }"></span>{{ s.label }}
            </button>
          </div>
        </div>
        <!-- 「在文件夹内查找」（原生的 "Look inside folders"，
             键 = filters[folder_search]，文案源 projects.index.filters_modal.folders.label）。
             ⚠ 它的作用是「把筛选范围从当前层级扩到所有文件夹内部」——
               勾上之后表格**不再渲染文件夹行**，只出项目行（服务端 Lists::ProjectsService#call
               的第一个分支）。这不是渲染细节，是**行集合会变**，所以必须在筛选面板里，
               不能做成工具栏上的一个纯前端开关。 -->
        <div class="field">
          <label class="field-label" title="勾选后筛选会同时作用于所有文件夹内部的实验/项目，表格只显示项目行">
            在文件夹内查找
          </label>
          <label class="check-row">
            <input
              v-model="ui.filters.folderSearch"
              type="checkbox"
              data-e2e="fp-folder-search"
            />
            <span>包含所有文件夹内部</span>
          </label>
        </div>
      </div>
      <div class="panel-footer">
        <button class="eln-btn-ghost" data-e2e="fp-clear" @click="clearAll">清除</button>
        <button class="eln-btn-primary" data-e2e="fp-apply" @click="applyFilters">显示结果</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue/dist/vue.esm-bundler.js'
import { ui, closeFilter, resetFilters, applyFilters, refreshList } from '../../store/ui'
import { members } from '../../data/mock'
import AppIcon from '../AppIcon.vue'

// ⚠ 兜底常量必须先声明（<script setup> 的 TDZ）：真机没给选项时用这三档固定状态。
// 值与原生 Lists::ProjectsService 的 scopes 键一致（not_started/in_progress/done），
// 不是 MyModuleStatus 的 id，也不是原型行状态那套 active/notstarted/done。
const PROTOTYPE_STATUSES = [
  { value: 'not_started', label: '未开始', color: 'var(--status-notstarted)' },
  { value: 'in_progress', label: '进行中', color: 'var(--status-active)' },
  { value: 'done', label: '已完成', color: 'var(--status-done)' }
]

const STATUS_COLOR = {
  not_started: 'var(--status-notstarted)',
  in_progress: 'var(--status-active)',
  done: 'var(--status-done)'
}

// 真机：payload 给 [{id, name}]；原型独立跑：mock 只有名字 → 退化成 id=name 的同构结构，
// 模板里的 v-for 就不用分叉。
const memberOptions = computed(() =>
  ui.members && ui.members.length ? ui.members : members.map((m) => ({ id: m.name, name: m.name }))
)

const headOptions = computed(() =>
  ui.headOfProjects && ui.headOfProjects.length ? ui.headOfProjects : memberOptions.value
)

const statusOptions = computed(() =>
  ui.statuses && ui.statuses.length
    ? ui.statuses.map((s) => ({
        value: s.id,
        label: s.name,
        color: STATUS_COLOR[s.id] || 'var(--color-border-strong)'
      }))
    : PROTOTYPE_STATUSES
)

function toggleStatus(v) {
  const i = ui.filters.statuses.indexOf(v)
  if (i === -1) ui.filters.statuses.push(v)
  else ui.filters.statuses.splice(i, 1)
}

async function clearAll() {
  resetFilters()
  await refreshList()
}
</script>

<style scoped>
.overlay-backdrop {
  position: fixed;
  inset: 0;
  z-index: 40;
}
.filter-panel {
  position: absolute;
  right: 60px;
  top: 150px;
  width: 400px;
  max-height: 76vh;
  display: flex;
  flex-direction: column;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-pop);
  overflow: hidden;
}
.panel-header {
  height: 52px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 16px;
  border-bottom: 1px solid var(--color-divider);
}
.panel-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.close-btn {
  width: 28px;
  height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  border-radius: 6px;
  color: var(--color-text-secondary);
}
.close-btn:hover {
  background: var(--color-fill-soft);
}
.panel-body {
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 16px;
  overflow-y: auto;
}
.field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.field-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.field-input {
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: var(--color-card);
  outline: none;
}
.field-input.multi {
  height: auto;
  padding: 6px;
}
/* 「在文件夹内查找」勾选行：与 .field-input 同高，保证面板纵向节奏一致 */
.check-row {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 36px;
  font-size: 13px;
  color: var(--color-text-menu);
  cursor: pointer;
}
.check-row input {
  width: 15px;
  height: 15px;
  accent-color: var(--color-primary);
}
.field-input:focus {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}
.range {
  display: flex;
  align-items: center;
  gap: 8px;
}
.range .field-input {
  flex: 1;
  min-width: 0;
}
.range-sep {
  font-size: 12px;
  color: var(--color-placeholder);
  flex-shrink: 0;
}
.status-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.status-chip {
  display: inline-flex;
  align-items: center;
  height: 30px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-chip);
  background: var(--color-card);
  font-size: 12px;
  color: var(--color-text-secondary);
  transition: all 0.12s ease;
}
.status-chip.on {
  background: var(--color-active-bg);
  border-color: var(--color-primary);
  color: var(--color-primary);
  font-weight: 500;
}
.panel-footer {
  height: 60px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 0 16px;
  border-top: 1px solid var(--color-divider);
}
</style>
