<template>
  <!-- 新建文件夹模态（与 NewProjectModal 同壳）
       真机：POST 原生 /project_folders，强参数只有
       project_folder[name|parent_folder_id|archived] —— 归档态建的文件夹直接是归档的，
       与原生 new_folder.vue 的行为一致（archived: viewMode === 'archived'）。 -->
  <div v-if="ui.newFolderOpen" class="modal-backdrop" @click.self="closeNewFolder">
    <div class="modal eln-card">
      <div class="modal-header">
        <span class="modal-title">新建文件夹</span>
        <button class="close-btn" @click="closeNewFolder"><AppIcon name="close" :size="16" /></button>
      </div>
      <div class="modal-body">
        <div class="field">
          <label class="field-label">文件夹名称 <span class="req">*</span></label>
          <input
            v-model="name"
            class="field-input"
            placeholder="输入文件夹名称"
            data-e2e="nf-name"
            @keyup.enter="submit"
          />
        </div>
        <div v-if="parentOptions.length" class="field">
          <label class="field-label">上级文件夹</label>
          <select v-model="parentId" class="field-input">
            <option value="">顶层</option>
            <option v-for="f in parentOptions" :key="f.id" :value="f.id">{{ f.name }}</option>
          </select>
        </div>
        <div v-if="error" class="form-error" data-e2e="nf-error">{{ error }}</div>
      </div>
      <div class="modal-footer">
        <button class="eln-btn-ghost" @click="closeNewFolder">取消</button>
        <button
          class="eln-btn-primary"
          :disabled="submitting || !name.trim()"
          data-e2e="nf-submit"
          @click="submit"
        >{{ submitting ? '创建中…' : '创建' }}</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue/dist/vue.esm-bundler.js'
import { ui, closeNewFolder, createFolder } from '../../store/ui'
import AppIcon from '../AppIcon.vue'

const name = ref('')
const parentId = ref('')
const submitting = ref(false)
const error = ref('')

// 上级文件夹候选 = 同一个文件夹列表（原生也是拿 folders_tree 那一批）
const parentOptions = computed(() => ui.folders || [])

async function submit() {
  if (!name.value.trim() || submitting.value) return
  error.value = ''
  submitting.value = true
  try {
    await createFolder({ name: name.value.trim(), parentId: parentId.value })
    name.value = ''
    parentId.value = ''
  } catch (e) {
    error.value = e && e.message ? e.message : '创建失败'
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
.modal-backdrop {
  position: fixed;
  inset: 0;
  z-index: 50;
  background: rgba(24, 24, 27, 0.4);
  display: flex;
  align-items: center; /* 与 NewProjectModal 同款：真居中 */
  justify-content: center;
  padding: 24px;
}
.modal {
  /* 同 NewProjectModal：抵消宿主 Bootstrap 全局 `.modal{position:fixed;top:0;left:0}` */
  position: relative;
  inset: auto;
  height: auto;
  width: 520px;
  max-height: calc(100vh - 48px);
  display: flex;
  flex-direction: column;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-modal);
  overflow: hidden;
}
.modal-header {
  height: 60px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  border-bottom: 1px solid var(--color-divider);
}
.modal-title {
  font-size: 16px;
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
.modal-body {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 18px;
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
.field-input:focus {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}
.form-error {
  font-size: 12px;
  color: var(--color-danger, #DC2626);
}
.req {
  color: var(--color-danger);
}
.modal-footer {
  height: 64px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 0 20px;
  border-top: 1px solid var(--color-divider);
}
</style>
