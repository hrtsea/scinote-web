<!--
  行菜单行动浮层（编辑 / 移动 / 访问权限 / 评论 四体同一容器）。

  铁律：所有端点 URL 由 payload 下发（row.actions[].url），本组件不拼宿主义定路由。
  真源映射（与 payload#row_actions 的注释表一一对应）：
    edit    → PATCH  <project_path>                    原生 projects#update
    move    → PATCH  <project_path> {project_folder_id}；目标树 GET /project_folders/tree
    access  → GET/POST/PATCH/DELETE /access_permissions/projects/:id（原生 AccessPermissions::ProjectsController）
    comment → GET /comments?object_type=Project&object_id=:id（原生 shared/comments/_comments_list partial）
              POST /comments 发评论、DELETE /comments/:id 删评论

  🔴 原型独立跑（无 payload）：所有 fetch 都拿不到 url → 显式报错文案，
     绝不拿原型演示值假装成功。
-->
<template>
  <div v-if="ui.rowAction" class="modal-backdrop" @click.self="close">
    <div class="modal eln-card" data-e2e="row-action-modal">
      <div class="modal-header">
        <span class="modal-title">{{ title }}</span>
        <button class="close-btn" @click="close" data-e2e="row-action-close">
          <AppIcon name="close" :size="16" />
        </button>
      </div>

      <div class="modal-body" data-e2e="row-action-body">
        <!-- ---------- 编辑（原生 projects#update / project_folders#update 白名单） ---------- -->
        <template v-if="ui.rowAction.kind === 'edit'">
          <div class="field">
            <label class="field-label">{{ isFolder ? '文件夹名称' : '项目名称' }} <span class="req">*</span></label>
            <input v-model="form.name" class="field-input" data-e2e="ra-edit-name" />
          </div>
          <!-- 文件夹只有名称可改（原生 project_folders#update 的 permit 就是
               name / parent_folder_id / archived 三个，parent_folder_id 属于「移动」那一支，
               这里改它会把两次动作混在一起）。所以项目专属的日期/描述/归入文件夹
               在文件夹行上一律**不渲染** —— 不是渲染再置灰。 -->
          <template v-if="!isFolder">
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
              <textarea v-model="form.desc" class="field-textarea" rows="3"></textarea>
            </div>
            <div v-if="folderOptions.length" class="field">
              <label class="field-label">归入文件夹</label>
              <select v-model="form.folderId" class="field-input" data-e2e="ra-edit-folder">
                <option value="">不归入（顶层）</option>
                <option v-for="f in folderOptions" :key="f.id" :value="f.id">{{ f.name }}</option>
              </select>
            </div>
          </template>
        </template>

        <!-- ---------- 移动（原生 /project_folders/tree + /project_folders/move_to） ---------- -->
        <template v-else-if="ui.rowAction.kind === 'move'">
          <div class="field">
            <label class="field-label">移动到</label>
            <select v-model="folderId" class="field-input" data-e2e="ra-move-folder">
              <option value="">{{ isFolder ? '顶层' : '项目列表（顶层）' }}</option>
              <option v-for="f in folders" :key="f.id" :value="f.id" :data-e2e="'ra-move-opt-' + f.id">
                {{ f.name }}
              </option>
            </select>
          </div>
          <div class="block-note">
            目标清单来自原生 <code>GET /project_folders/tree</code>；落库走原生
            <code>POST /project_folders/move_to</code>
            （<code>movables[].type</code> = {{ isFolder ? 'project_folders' : 'projects' }}）。
          </div>
        </template>

        <!-- ---------- 删除文件夹（原生 project_folders#destroy） ---------- -->
        <!-- 破坏性动作，必须先说清后果再让点确认；不做成「点一下就发」的直发动作。 -->
        <template v-else-if="ui.rowAction.kind === 'delete'">
          <div class="block-note danger-note" data-e2e="ra-delete-warning">
            将删除文件夹「{{ activeRow && activeRow.name }}」（{{ activeRow && activeRow.code }}）。
            此操作不可撤销。
          </div>
          <div class="block-note">
            原生 <code>POST /project_folders/destroy</code> 只删除**空文件夹** ——
            里面有项目或子文件夹时服务端会直接拒绝（那不是故障，是保护）。
          </div>
        </template>

        <!-- ---------- 访问权限（原生 AccessPermissions::ProjectsController） ---------- -->
        <template v-else-if="ui.rowAction.kind === 'access'">
          <div v-if="error" class="form-error" data-e2e="ra-access-error">{{ error }}</div>
          <div class="access-list" data-e2e="ra-access-list">
            <div v-if="!assignments.length" class="block-note">该项目还没有显式指派的成员。</div>
            <div v-for="a in assignments" :key="a.id" class="access-row">
              <span class="access-name" data-e2e="ra-access-name">{{ a.user ? a.user.name : '—' }}</span>
              <select
                class="field-input access-role"
                :data-e2e="'ra-access-role-' + a.id"
                :value="a.user_role ? a.user_role.id : ''"
                @change="changeRole(a, $event)"
              >
                <option v-for="r in roles" :key="r.id" :value="r.id">{{ r.name }}</option>
              </select>
              <button class="link-btn danger" @click="removeMember(a)" data-e2e="ra-access-remove">
                移除
              </button>
            </div>
          </div>
          <div class="field">
            <label class="field-label">添加成员</label>
            <div class="field-row">
              <select v-model="addUserId" class="field-input" data-e2e="ra-access-add-user">
                <option value="">选择成员…</option>
                <option v-for="m in assignable" :key="m.id" :value="m.id">
                  {{ m.name || (m.initial ? `${m.initial} · ${m.name}` : m.name) }}
                </option>
              </select>
              <select v-model="addRoleId" class="field-input" data-e2e="ra-access-add-role">
                <option v-for="r in roles" :key="r.id" :value="r.id">{{ r.name }}</option>
              </select>
              <button class="eln-btn-primary" :disabled="!addUserId" @click="addMember" data-e2e="ra-access-add">
                添加
              </button>
            </div>
          </div>
        </template>

        <!-- ---------- 评论（原生 /comments + shared/comments/_comments_list partial） ---------- -->
        <template v-else-if="ui.rowAction.kind === 'comment'">
          <div class="comments-box" data-e2e="ra-comment-box" v-html="commentHtml"></div>
          <div v-if="error" class="form-error" data-e2e="ra-comment-error">{{ error }}</div>
          <div class="field">
            <textarea
              v-model="message"
              class="field-textarea"
              rows="2"
              placeholder="输入评论…"
              data-e2e="ra-comment-input"
            ></textarea>
          </div>
        </template>

        <div v-if="error" class="form-error" data-e2e="ra-error">{{ error }}</div>
        <div v-if="loading" class="block-note" data-e2e="ra-loading">加载中…</div>
      </div>

      <div class="modal-footer">
        <button class="eln-btn-ghost" @click="close">取消</button>
        <button
          v-if="['edit', 'move', 'delete'].includes(ui.rowAction.kind)"
          class="eln-btn-primary"
          :class="{ 'eln-btn-danger': ui.rowAction.kind === 'delete' }"
          :disabled="submitting || (ui.rowAction.kind === 'edit' && !form.name.trim())"
          data-e2e="ra-submit"
          @click="submit"
        >
          {{ submitting ? '提交中…' : submitLabel }}
        </button>
        <button
          v-else-if="ui.rowAction.kind === 'comment'"
          class="eln-btn-primary"
          :disabled="submitting || !message.trim()"
          data-e2e="ra-comment-submit"
          @click="postComment"
        >
          {{ submitting ? '发送中…' : '发送' }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue/dist/vue.esm-bundler.js'
import { ui, closeRowAction, sendForm, showToast, refreshList } from '../../store/ui'
import AppIcon from '../AppIcon.vue'

// 标题按「动作 + 行类型」两个维度定 —— V1.32 起同一个 kind（edit/move）在项目行
// 与文件夹行上是两件事（PATCH /projects/:id vs PATCH /project_folders/:id），
// 标题不分开写就会出现「编辑文件夹」的弹窗标题写着「编辑项目」。
const TITLE = {
  project: { edit: '编辑项目', move: '移动到文件夹', access: '项目访问权限', comment: '项目评论' },
  folder: { edit: '重命名文件夹', move: '移动文件夹', delete: '删除文件夹' }
}
// ⚠ 名字故意叫 activeRow 而不是 row：本文件里 `reset()` / `loadMove()` / `submit()`
//   里都各有一个**局部** `const row = ui.rowAction.row`，外层再叫 row 就会被遮蔽
//   （JS 允许遮蔽，但下次有人在局部里改 `row.value` 就会静默拿到错的对象）。
const activeRow = computed(() => (ui.rowAction ? ui.rowAction.row : null))
const isFolder = computed(() => !!(activeRow.value && activeRow.value.folder))
const title = computed(() => {
  const kind = ui.rowAction ? ui.rowAction.kind : ''
  const table = isFolder.value ? TITLE.folder : TITLE.project
  return table[kind] || (isFolder.value ? '文件夹操作' : '项目操作')
})
// 确认按钮文案：删除是破坏性动作，写「删除」而不是「保存」——「保存」会让人以为可撤销。
const submitLabel = computed(() => (ui.rowAction && ui.rowAction.kind === 'delete' ? '删除' : '保存'))

const loading = ref(false)
const submitting = ref(false)
const error = ref('')

// ---------- 编辑表单 ----------
const form = reactive({ name: '', start: '', due: '', desc: '', folderId: '' })
const folderOptions = computed(() => {
  const row = ui.rowAction ? ui.rowAction.row : null
  return row && row.actions && row.actions.move ? ui.folders || [] : []
})

// ---------- 移动 ----------
const folders = ref([])
const folderId = ref('')

// ---------- 访问权限 ----------
const assignments = ref([])
const roles = ref([])
const addUserId = ref('')
const addRoleId = ref('')

// ---------- 评论 ----------
const commentHtml = ref('')
const message = ref('')

// 「添加成员」下拉的真源：原生 projects#users_filter（GET /projects/users_filter）。
//
// 🔴 这里**不是** /access_permissions/projects/new —— 那个端点实测 404（详见
//    ProjectListPayload#assignable_users_path_of）：ProjectsController#set_model 用
//    find_by(id: params[:id])，而 #new 的 params[:id] 恒为 "new" → render_404。
//    候选名单的「排除已指派」谓词只能由前端用 #show 的成员列表补上（见下方 assignable）。
//
// 不注入 assignableUsersUrl 时保持空数组 = **显式留白**（下拉只剩占位），
// 绝不拿原型演示名单冒充可指派成员。
const assignableUsers = ref([])

// 真源形状三种都收（后端改口径也不会整条断掉，只是退化成占位）：
//   1) users_filter：`{data:[[id, name, {avatar_url}], ...]}` ← 原生在服役的那条
//   2) JSON:API     ：`{data:[{id,type,attributes:{...}}]}`
//   3) 裸数组       ：`[{id, name}, ...]`
function normalizeUserTuples(raw) {
  const list = Array.isArray(raw) ? raw : (raw && raw.data) || []
  return list.map((x) => {
    if (Array.isArray(x)) {
      // users_filter 的元组：第一个是 id、第二个是显示名
      if (x.length < 2) return null
      return { id: x[0], name: x[1] }
    }
    if (x && x.attributes) return { ...x.attributes, id: x.id || x.attributes.id }
    return x
  }).filter((x) => x && x.id)
}

async function loadAssignableUsers() {
  const url = ui.assignableUsersUrl
  if (!url) {
    assignableUsers.value = []
    return
  }
  try {
    const data = await fetchJson(url)
    assignableUsers.value = normalizeUserTuples(data)
  } catch (e) {
    error.value = e && e.message ? e.message : '可指派成员拉取失败'
    assignableUsers.value = []
  }
}

const assignable = computed(() => {
  const ids = new Set((assignments.value || []).map((a) => a.user && a.user.id))
  return assignableUsers.value.filter((m) => m && m.id && !ids.has(m.id))
})

function reset() {
  loading.value = false
  submitting.value = false
  error.value = ''
  message.value = ''
  const row = ui.rowAction ? ui.rowAction.row : null
  if (!row) return
  form.name = row.name || ''
  form.start = row.startDate || ''
  form.due = row.due || ''
  form.desc = row.description || ''
  form.folderId = row.actions && row.actions.move ? row.folderId || '' : ''
  folderId.value = ''
}

async function loadMove() {
  const row = ui.rowAction.row
  const treeUrl = row.actions.move.folders_tree_url
  if (!treeUrl) {
    error.value = 'payload 未下发文件夹树端点（/project_folders/tree），无法拉目标清单'
    return
  }
  loading.value = true
  try {
    const res = await fetch(treeUrl, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const data = await res.json()
    // 原生 /project_folders/tree 返回 { data: [ { id, name, parent_folder_id, ... } ] }，
    // 坑：有的版本给的是嵌套 children。两种都收，展平成一层。
    // ⚠ 原生 /project_folders/tree 的真实形状（ProjectsHelper#folders_tree）：
    //   [{ folder: { id, name, parent_folder_id }, children: [ ... ] }, ...]
    //   —— 文件夹在 **folder** 键里，不是顶层。此前按 n.id / n.name 读 → 清一色
    //   undefined，下拉只剩一个「顶层」可选项，看着像"没有文件夹"的假绿。
    const list = Array.isArray(data) ? data : data.data || []
    const flat = []
    const walk = (nodes, depth) => {
      ;(nodes || []).forEach((n) => {
        const f = n.folder || n
        flat.push({ id: f.id, name: `${'　'.repeat(depth)}${f.name}` })
        if (n.children) walk(n.children, depth + 1)
      })
    }
    walk(list, 0)
    folders.value = flat
  } catch (e) {
    error.value = e && e.message ? e.message : '文件夹树拉取失败'
  } finally {
    loading.value = false
  }
}

async function loadAccess() {
  const url = ui.rowAction.row.actions.access.url
  if (!url) {
    error.value = 'payload 未下发访问权限端点，无法读取成员'
    return
  }
  loading.value = true
  try {
    const [a, r] = await Promise.all([
      fetchJson(url),
      fetchJson(`${url}/user_roles`)
    ])
    //
    // 🔴 原生 show（AccessPermissions::ProjectsController#show）虽然写的是
    //    `render json: <ua relation>, each_serializer: UserAssignmentSerializer`，
    //    但 AMS 一渲染集合就套上 **JSON:API 形状**：
    //      { data: [ { id: "152", type: "user_assignments",
    //                  attributes: { assigned, assignable_type, user: {...},
    //                                user_role: {...}, last_owner, current_user } } ] }
    //    —— **不是**普通数组，user/user_role 都**埋在 attributes 里**。
    //    直接按 a.user 读 → undefined → 下拉永远空 value、改名时 user_id 拿不到。
    //    （本轮真机验收抓出来的：`option value="Owner">1`、select value="" 就是它。）
    const rawList = Array.isArray(a) ? a : (a && a.data) || []
    assignments.value = rawList.map((x) =>
      x && x.attributes ? { ...x.attributes, id: x.id || x.attributes.id } : x
    )
    // ⚠ user_roles 回的是 { data: [[...], ...], default_role_id } —— **二维数组（元组）**，
    //   不是对象数组。edit.vue 里用的也是 role[0]/role[1] 这种下标取法。
    //   🔴 而且元组方向是反的：UserRolesHelper#user_roles_collection 生成的是
    //      [display_name, id]，但 AccessPermissions::BaseController#user_roles 又
    //      `.map(&:reverse)` 了一遍 → 实际流到前端的是 **[id, display_name]**。
    //      （照 [name, id] 去解会整个反：option 变成 value="Owner">1，
    //        select 显示空、原生 update 也会拿错 id —— 真机验收才抓到。）
    const raw = (r && r.data) || []
    roles.value = raw.map((x) => {
      if (!Array.isArray(x)) return x
      // 谁在前是数字谁就是 id：原生当前是 [id, name]，但向后兼容两种写法
      return x[0] !== '' && !Number.isNaN(Number(x[0])) ? { id: x[0], name: x[1] } : { id: x[1], name: x[0] }
    })
    if (addRoleId.value === '') {
      const first = roles.value[0]
      if (first) addRoleId.value = first.id
    }
  } catch (e) {
    error.value = e && e.message ? e.message : '成员列表拉取失败'
  } finally {
    loading.value = false
  }
}

async function fetchJson(url) {
  const res = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const text = await res.text()
  try {
    return text ? JSON.parse(text) : null
  } catch (_) {
    return text
  }
}

/**
 * 改角色 —— 照原生 shared/access_modal/edit.vue#changeRole 的口径：
 *   PUT /access_permissions/projects/:project_id
 *   body { user_assignment: { user_id, user_role_id } }
 * 🔴 两个和先前写错的地方（2026-10-06 真机验收抓出）：
 *   1. 不是 PATCH `${url}/${assignment.id}` —— 那条路由根本不存在
 *      （access_permissions 只有 /projects/:id，没有嵌套的 /projects/:id/:ua_id）；
 *      原生是**用 body 里的 user_id 反查**那条 assignment 的（set_assignment）。
 *   2. body 必须带 user_id，否则 assignment_type 算出 undefined → find_or_initialize_by 拿不到。
 */
async function changeRole(a, e) {
  const url = ui.rowAction.row.actions.access.url
  if (!url || !a || !a.user) return
  submitting.value = true
  error.value = ''
  try {
    await sendForm(url, 'PUT', {
      user_assignment: { user_id: a.user.id, user_role_id: e.target.value }
    })
    a.user_role = { id: e.target.value, name: (roles.value.find((r) => String(r.id) === String(e.target.value)) || {}).name }
  } catch (err) {
    error.value = err.message || '角色更新失败'
  } finally {
    submitting.value = false
  }
}

async function addMember() {
  const url = ui.rowAction.row.actions.access.url
  if (!url || !addUserId.value) return
  submitting.value = true
  error.value = ''
  try {
    await sendForm(url, 'POST', {
      user_assignment: { user_id: addUserId.value, user_role_id: addRoleId.value }
    })
    addUserId.value = ''
    await loadAccess()
  } catch (err) {
    error.value = err.message || '添加成员失败'
  } finally {
    submitting.value = false
  }
}

/**
 * 移除成员 —— 照原生 edit.vue#removeRole：
 *   DELETE /access_permissions/projects/:project_id，**带 body**
 *   body { user_assignment: { user_id } }
 * ⚠ 原生是 axios.delete(url, { data }) —— DELETE 也走 body；
 *   我们沿用同一口径（Rails 会解析 JSON body）。不带 user_id 原生就删错人/删不掉。
 */
async function removeMember(a) {
  const url = ui.rowAction.row.actions.access.url
  if (!url || !a || !a.user) return
  submitting.value = true
  error.value = ''
  try {
    await sendForm(url, 'DELETE', { user_assignment: { user_id: a.user.id } })
    assignments.value = assignments.value.filter((x) => x.id !== a.id)
  } catch (err) {
    error.value = err.message || '移除成员失败'
  } finally {
    submitting.value = false
  }
}

async function loadComments() {
  const url = ui.rowAction.row.actions.comment.url
  if (!url) {
    error.value = 'payload 未下发评论端点，无法读取真实评论'
    return
  }
  loading.value = true
  try {
    const data = await fetchJson(url)
    // 原生 CommentsController#index 回 { object_name, object_url, comment_addable, comments: "<html>" }
    commentHtml.value = data && data.comments ? data.comments : ''
  } catch (e) {
    error.value = e && e.message ? e.message : '评论拉取失败'
  } finally {
    loading.value = false
  }
}

// 评论发送端点：payload 只给了 index（带 query），去掉 query 就是原生 /comments
function commentsBaseUrl() {
  const url = ui.rowAction.row.actions.comment.url
  return url ? url.split('?')[0] : ''
}

async function postComment() {
  const base = commentsBaseUrl()
  if (!base) {
    error.value = 'payload 未下发评论端点'
    return
  }
  if (!message.value.trim()) return
  submitting.value = true
  error.value = ''
  try {
    await sendForm(base, 'POST', {
      object_type: 'Project',
      object_id: ui.rowAction.row.id,
      message: message.value
    })
    message.value = ''
    await loadComments()
  } catch (err) {
    error.value = err.message || '评论发送失败'
  } finally {
    submitting.value = false
  }
}

async function submit() {
  const row = ui.rowAction.row
  const kind = ui.rowAction.kind
  const act = row.actions[kind]
  const folder = !!row.folder
  submitting.value = true
  error.value = ''
  try {
    if (kind === 'edit') {
      if (folder) {
        // 文件夹改名：原生 project_folders#update，强参数 project_folder[name]。
        // ⚠ 键名是 `project_folder`（单数），不是 `project` —— 发错原生 `require(:project_folder)`
        //   直接 400/ParameterMissing。
        await sendForm(act.url, 'PATCH', { project_folder: { name: form.name } })
      } else {
        // ⚠ projects#update 的 permit 白名单**不含 project_folder_id**，
        //   所以编辑弹窗里的「归入文件夹」下拉只影响本页的展示，不参与落库
        //   （真移动走 move 这一支）。这里没把 project_folder_id 发出去，
        //   免得发出去被原生静默吞掉、还 toast「已保存」——那是彻头彻尾的假通。
        const body = {
          project: {
            name: form.name,
            start_date: form.start || '',
            due_date: form.due || '',
            description: form.desc || ''
          }
        }
        await sendForm(act.url, 'PATCH', body)
      }
    } else if (kind === 'move') {
      // 原生 modals/move.vue#submit 的 body 一字不改：
      //   顶层 = 'root_folder'（和原生 selectFolder(null) 一个意思），否则传文件夹 id；
      //   movables 固定 [{ id, type }]，type 原生用来区分 project / folder。
      //   🔴 文件夹行的 type 必须是 `project_folders`（**复数**）—— 原生 move_folders
      //     那一支按这个字符串分流；写成单数会走进 move_projects，然后静默"成功"却什么都没动。
      const rootKey = act.root_key || 'root_folder'
      await sendForm(act.url, 'POST', {
        destination_folder_id: folderId.value || rootKey,
        movables: [{ id: row.id, type: folder ? 'project_folders' : 'projects' }]
      })
    } else if (kind === 'delete') {
      // 原生 project_folders#destroy：POST + `project_folder_ids`（**数组**）。
      const bodyKey = act.body_key || 'project_folder_ids'
      const body = {}
      body[bodyKey] = [row.id]
      await sendForm(act.url, 'POST', body)
    }
    closeRowAction()
    showToast(
      kind === 'delete'
        ? '文件夹已删除'
        : (folder ? '已保存（原生 project_folders#update）' : '已保存（原生 projects#update）')
    )
    await refreshList()
  } catch (e) {
    error.value = e && e.message ? e.message : '保存失败'
  } finally {
    submitting.value = false
  }
}

function close() {
  closeRowAction()
}

watch(
  () => ui.rowAction && ui.rowAction.kind,
  (kind) => {
    error.value = ''
    message.value = ''
    reset()
    if (kind === 'move') loadMove()
    if (kind === 'access') {
      loadAccess()
      loadAssignableUsers()
    }
    if (kind === 'comment') loadComments()
  },
  { immediate: true }
)

onMounted(reset)
</script>

<style scoped>
.modal-backdrop {
  position: fixed;
  inset: 0;
  z-index: 70;
  background: rgba(24, 24, 27, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}
.modal {
  /* 与 NewProjectModal 同一个坑：宿主 Bootstrap 全局 .modal 是 position:fixed + inset:0 */
  position: relative;
  inset: auto;
  height: auto;
  width: 560px;
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
.field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.field-row {
  display: flex;
  gap: 12px;
}
.field-row .field {
  flex: 1;
}
.field-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
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
}
.field-textarea {
  height: auto;
  padding: 8px 12px;
  resize: vertical;
}
.field-input:focus,
.field-textarea:focus {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}
.form-error {
  font-size: 12px;
  color: var(--color-danger, #dc2626);
}
.req {
  color: var(--color-danger);
}
.block-note {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.block-note code {
  font-size: 11px;
}
/* 破坏性动作的告示（删除文件夹）：比普通说明更醒目，别让人误点确认 */
.danger-note {
  padding: 10px 12px;
  border-radius: 8px;
  background: rgba(220, 38, 38, 0.06);
  border: 1px solid rgba(220, 38, 38, 0.22);
  color: var(--color-danger, #dc2626);
  font-size: 13px;
}
/* 确认按钮的破坏态：与 .eln-btn-primary 同形，只换底色 */
.eln-btn-danger {
  background: var(--color-danger, #dc2626) !important;
  border-color: var(--color-danger, #dc2626) !important;
  color: #fff !important;
}
.access-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-height: 240px;
  overflow-y: auto;
}
.access-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 10px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
}
.access-name {
  flex: 1;
  font-size: 13px;
}
.access-role {
  width: 180px;
}
.link-btn {
  border: none;
  background: transparent;
  color: var(--color-primary);
  font-size: 13px;
  cursor: pointer;
}
.link-btn.danger {
  color: var(--color-danger, #dc2626);
}
.comments-box {
  max-height: 320px;
  overflow-y: auto;
  font-size: 13px;
  line-height: 1.6;
}
</style>
