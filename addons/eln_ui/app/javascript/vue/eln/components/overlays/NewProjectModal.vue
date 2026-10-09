<template>
  <!-- 新建项目模态（画布 40:62）：520 宽白底边框圆角12 -->
  <div v-if="ui.newProjectOpen" class="modal-backdrop" @click.self="closeNewProject">
    <div class="modal eln-card">
      <div class="modal-header">
        <span class="modal-title">创建新项目</span>
        <button class="close-btn" @click="closeNewProject"><AppIcon name="close" :size="16" /></button>
      </div>
      <div class="modal-body">
        <div class="field">
          <label class="field-label">项目名称 <span class="req">*</span></label>
          <input v-model="form.name" class="field-input" placeholder="输入项目名称" data-e2e="np-name" />
        </div>
        <div class="field-row">
          <div class="field">
            <label class="field-label">开始日期</label>
            <input v-model="form.start" type="date" class="field-input" />
          </div>
          <div class="field">
            <label class="field-label">截止日期</label>
            <input v-model="form.due" type="date" class="field-input" />
          </div>
        </div>
        <div class="field">
          <label class="field-label">描述</label>
          <textarea v-model="form.desc" class="field-textarea" rows="3" placeholder="补充项目背景与目标（选填）"></textarea>
        </div>
        <div v-if="folderOptions.length" class="field">
          <label class="field-label">归入文件夹</label>
          <select v-model="form.folderId" class="field-input">
            <option value="">不归入（顶层）</option>
            <option v-for="f in folderOptions" :key="f.id" :value="f.id">{{ f.name }}</option>
          </select>
        </div>
        <!--
          可见性 / 默认用户角色 —— 与原生落点的对应关系（别照原型当成两个独立字段）：
            原生没有「可见性」这一列；它实际由 projects.default_public_user_role_id 表达：
              留空      = 只给显式指派的人可见（= 原型的「仅项目成员可见」）
              设成角色  = 全队按该角色可见（= 原型的「全单位可见」）
            projects#create 之后由 create_team_assignment 读
            params[:project][:default_public_user_role_id] 建一张 TeamAssignment。
            所以这里选「仅项目成员可见」时角色 id **不发出去**，不编一个原生不存在的列。
        -->
        <div class="field">
          <label class="field-label">可见性</label>
          <select v-model="form.visibility" class="field-input">
            <option value="members">仅项目成员可见</option>
            <option value="team">全单位可见（按下面的角色）</option>
          </select>
        </div>
        <div class="field">
          <label class="field-label">默认用户角色</label>
          <select v-model="form.roleId" class="field-input" :disabled="form.visibility !== 'team'">
            <option v-for="r in roleOptions" :key="r.id" :value="r.id">{{ r.name }}</option>
          </select>
        </div>
        <div v-if="error" class="form-error" data-e2e="np-error">{{ error }}</div>
      </div>
      <div class="modal-footer">
        <button class="eln-btn-ghost" @click="closeNewProject">取消</button>
        <button
          class="eln-btn-primary"
          :disabled="submitting || !form.name.trim()"
          data-e2e="np-submit"
          @click="create"
        >{{ submitting ? '创建中…' : '创建' }}</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, reactive, ref } from 'vue/dist/vue.esm-bundler.js'
import { ui, closeNewProject, createProject } from '../../store/ui'
import AppIcon from '../AppIcon.vue'

// 原型独立跑时 payload 没给选项 → 这两个下拉退化成原型那四个字符串常量，
// 组件照样能打开、能点，只是 create() 里发现没有 createUrls 就只关弹窗不发包。
const PROTOTYPE_ROLES = [
  { id: 'Owner', name: 'Owner' },
  { id: 'Normal user', name: 'Normal user' },
  { id: 'Technician', name: 'Technician' },
  { id: 'Viewer', name: 'Viewer' }
]

const roleOptions = computed(() =>
  ui.defaultRoles && ui.defaultRoles.length ? ui.defaultRoles : PROTOTYPE_ROLES
)

const folderOptions = computed(() => ui.folders || [])

const submitting = ref(false)
const error = ref('')

const form = reactive({
  name: '',
  start: '',
  due: '',
  desc: '',
  folderId: '',
  visibility: 'members',
  roleId: roleOptions.value[0] ? roleOptions.value[0].id : ''
})

async function create() {
  if (!form.name.trim() || submitting.value) return
  error.value = ''
  submitting.value = true
  try {
    await createProject(form)
    // 建完把表单归零，下次打开不是上次的残留值
    form.name = ''
    form.start = ''
    form.due = ''
    form.desc = ''
    form.folderId = ''
  } catch (e) {
    // 原生校验失败会把错误哈希回给前端（如 name: ['不能为空']）—— 必须显示出来，
    // 否则点了「创建」弹窗纹丝不动，看起来像没接。
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
  align-items: center; /* 用户要求：弹窗水平+垂直真居中（原为 flex-start + 12vh 顶部偏移） */
  justify-content: center;
  padding: 24px; /* 小视口不贴边 */
}
.modal {
  /* ⚠ 2026-10-04 真机抓到的坑：宿主 SciNote 自带 Bootstrap，全局 `.modal` 是
     `position: fixed; top: 0; left: 0; height: 100%`。scoped 样式里不写 position
     就会被它命中 —— 弹窗直接钉在视口左上角（水平偏差 540px），backdrop 的 flex
     居中完全失效。这里显式还原成普通流式盒子，居中才归 backdrop 管。 */
  position: relative;
  inset: auto;
  height: auto;
  width: 520px;
  max-height: calc(100vh - 48px); /* 与 backdrop 的 padding 联动，内容再高也在视口内 */
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
.field-row {
  display: flex;
  gap: 12px;
}
.field-row .field {
  flex: 1;
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
.form-error {
  font-size: 12px;
  color: var(--color-danger, #DC2626);
}
.req {
  color: var(--color-danger);
}
.field-input,
.field-textarea {
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: var(--color-card);
  outline: none;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.field-textarea {
  height: auto;
  padding: 8px 12px;
  resize: vertical;
}
.field-input::placeholder,
.field-textarea::placeholder {
  color: var(--color-placeholder);
}
.field-input:focus,
.field-textarea:focus {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
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
  background: var(--color-card);
}
</style>
