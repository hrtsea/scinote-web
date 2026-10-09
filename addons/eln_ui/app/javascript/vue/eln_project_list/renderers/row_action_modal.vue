<template>
  <!--
    行操作模态框（参照 V1 自包含 RowActionModal，改用原生 JSON 端点）。
    通过 <teleport to="body"> 渲染到 body，避免被 AG Grid 单元格的 overflow 裁剪。
    每个动作类型对应原生端点：
      edit      -> PATCH  row.actions.edit.url       （项目/文件夹基础字段）
      move      -> GET   row.actions.move.folders_tree_url（树） + POST move_to
      access    -> GET   row.actions.access.url（成员） + /user_roles（角色） + PUT/POST/DELETE
      comment   -> GET   row.actions.comment.url（评论列表） + POST（新增）
      export    -> POST  row.actions.export.url
      archive   -> POST  row.actions.archive.url  body {project_ids:[id]}
      delete    -> POST  row.actions.delete.url   body {project_folder_ids:[id]}
      activity  -> 由渲染器直接跳转（不在本模态框内处理）
  -->
  <teleport to="body">
    <div ref="modal" class="modal fade" tabindex="-1" role="dialog" :data-e2e="`e2e-MD-rowAction-${kind}`">
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-label="Close">
              <i class="sn-icon sn-icon-close"></i>
            </button>
            <h4 class="modal-title truncate !block" :data-e2e="`e2e-TX-rowAction-title`">
              {{ modalTitle }}
            </h4>
          </div>

          <div class="modal-body">
            <!-- 错误信息 -->
            <div v-if="error" class="alert alert-danger" data-e2e="e2e-TX-rowAction-error">
              {{ error }}
            </div>

            <!-- 加载中 -->
            <div v-if="loading" class="text-center py-4 text-muted">
              <i class="sn-icon sn-icon-loader animate-spin"></i> 加载中…
            </div>

            <!-- ============ 编辑（项目 / 文件夹） ============ -->
            <div v-if="kind === 'edit' && !loading">
              <div class="mb-3">
                <label class="sci-label">名称</label>
                <input type="text" v-model="form.name" class="sci-input-field" data-e2e="e2e-IF-rowAction-name" />
              </div>
              <template v-if="!isFolder">
                <div class="mb-3">
                  <label class="sci-label">开始日期</label>
                  <input type="date" v-model="form.startDate" class="sci-input-field" data-e2e="e2e-IF-rowAction-start" />
                </div>
                <div class="mb-3">
                  <label class="sci-label">截止日期</label>
                  <input type="date" v-model="form.due" class="sci-input-field" data-e2e="e2e-IF-rowAction-due" />
                </div>
                <div class="mb-3">
                  <label class="sci-label">描述</label>
                  <textarea v-model="form.description" class="sci-input-field" rows="3" data-e2e="e2e-IF-rowAction-desc"></textarea>
                </div>
              </template>
            </div>

            <!-- ============ 移动 ============ -->
            <div v-if="kind === 'move' && !loading">
              <label class="sci-label">目标文件夹</label>
              <select v-model="selectedFolder" class="sci-input-field" data-e2e="e2e-DD-rowAction-folder">
                <option value="root_folder">根目录</option>
                <option v-for="f in folderTree" :key="f.id" :value="String(f.id)">{{ f.name }}</option>
              </select>
            </div>

            <!-- ============ 访问权限 ============ -->
            <div v-if="kind === 'access' && !loading">
              <div v-if="assignableUsers.length" class="mb-3">
                <label class="sci-label">添加成员</label>
                <div class="flex gap-2">
                  <select v-model="newUserId" class="sci-input-field" data-e2e="e2e-DD-rowAction-addUser">
                    <option value="">选择用户…</option>
                    <option v-for="u in assignableUsers" :key="u.id" :value="String(u.id)">{{ u.name }}</option>
                  </select>
                  <select v-model="newRoleId" class="sci-input-field" data-e2e="e2e-DD-rowAction-addRole">
                    <option v-for="r in userRoles" :key="r.id" :value="String(r.id)">{{ r.name }}</option>
                  </select>
                  <button class="btn btn-primary" :disabled="!newUserId || busy" @click="addMember" data-e2e="e2e-BT-rowAction-add">
                    添加
                  </button>
                </div>
              </div>
              <table class="table" data-e2e="e2e-TB-rowAction-members">
                <thead>
                  <tr><th>成员</th><th>角色</th><th></th></tr>
                </thead>
                <tbody>
                  <tr v-for="m in members" :key="m.id">
                    <td>{{ m.name }}</td>
                    <td>
                      <select :value="String(m.roleId)" @change="changeRole(m, $event)" class="sci-input-field" :data-e2e="`e2e-DD-rowAction-role-${m.id}`">
                        <option v-for="r in userRoles" :key="r.id" :value="String(r.id)">{{ r.name }}</option>
                      </select>
                    </td>
                    <td>
                      <button class="btn btn-light icon-btn" @click="removeMember(m)" :data-e2e="`e2e-BT-rowAction-remove-${m.id}`">
                        <i class="sn-icon sn-icon-trash"></i>
                      </button>
                    </td>
                  </tr>
                  <tr v-if="!members.length"><td colspan="3" class="text-muted">暂无成员</td></tr>
                </tbody>
              </table>
            </div>

            <!-- ============ 评论 ============ -->
            <div v-if="kind === 'comment' && !loading">
              <div class="mb-3" v-html="commentsHtml" data-e2e="e2e-DV-rowAction-comments"></div>
              <div v-if="commentAddable">
                <textarea v-model="newComment" class="sci-input-field" rows="2" placeholder="写评论…" data-e2e="e2e-IF-rowAction-comment"></textarea>
              </div>
            </div>

            <!-- ============ 归档 / 导出 / 删除 确认 ============ -->
            <div v-if="['archive', 'export', 'delete'].includes(kind) && !loading">
              <p data-e2e="e2e-TX-rowAction-confirm">{{ confirmText }}</p>
            </div>
          </div>

          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-dismiss="modal" data-e2e="e2e-BT-rowAction-cancel">
              取消
            </button>
            <button
              v-if="showPrimary"
              type="button"
              class="btn btn-primary"
              :disabled="busy || primaryDisabled"
              :data-e2e="`e2e-BT-rowAction-primary`"
              @click="onPrimary"
            >
              {{ primaryLabel }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script>
import axios from 'custom_axios';

export default {
  name: 'ElnRowActionModal',
  props: {
    kind: { type: String, required: true },
    row: { type: Object, required: true },
    action: { type: Object, required: true }
  },
  emits: ['closed'],
  data() {
    return {
      loading: false,
      busy: false,
      error: '',
      // edit
      form: { name: '', startDate: '', due: '', description: '' },
      // move
      folderTree: [],
      selectedFolder: 'root_folder',
      // access
      members: [],
      userRoles: [],
      assignableUsers: [],
      newUserId: '',
      newRoleId: '',
      // comment
      commentsHtml: '',
      commentAddable: false,
      newComment: ''
    };
  },
  computed: {
    isFolder() {
      return this.row.type === 'project_folder';
    },
    modalTitle() {
      const map = {
        edit: this.isFolder ? '重命名文件夹' : '编辑项目',
        move: this.isFolder ? '移动文件夹' : '移动项目',
        access: '项目访问权限',
        comment: '项目评论',
        export: '导出项目',
        archive: '归档项目',
        delete: '删除文件夹'
      };
      return (map[this.kind] || '操作') + (this.row.attributes && this.row.attributes.name ? `：${this.row.attributes.name}` : '');
    },
    confirmText() {
      if (this.kind === 'archive') return '确定要归档该项目吗？此操作可在归档列表中恢复。';
      if (this.kind === 'export') return '确定要导出该项目吗？导出文件将发送到您的邮箱。';
      if (this.kind === 'delete') return '确定要删除该文件夹吗？文件夹内的项目将一并移动或处理。';
      return '';
    },
    showPrimary() {
      return !['comment'].includes(this.kind);
    },
    primaryLabel() {
      if (this.kind === 'delete') return '删除';
      if (this.kind === 'archive') return '归档';
      if (this.kind === 'export') return '导出';
      return '保存';
    },
    primaryDisabled() {
      if (this.kind === 'edit') return !this.form.name || this.busy;
      if (this.kind === 'move') return !this.selectedFolder || this.busy;
      if (this.kind === 'access') return this.busy;
      return this.busy;
    }
  },
  mounted() {
    this.init();
    const $ = window.jQuery || window.$;
    if ($ && this.$refs.modal) {
      $(this.$refs.modal)
        .on('hidden.bs.modal', () => this.$emit('closed'))
        .modal('show');
    }
  },
  beforeUnmount() {
    const $ = window.jQuery || window.$;
    if ($) {
      if (this.$refs.modal) {
        $(this.$refs.modal).off('hidden.bs.modal').modal('hide');
      }
      // 兜底清理：Vue 卸载 teleport 节点可能早于 Bootstrap 过渡结束，
      // 偶发遗留 .modal-backdrop 遮罩层拦截页面后续点击（参照 V1 自包含模态框卸载）。
      $('.modal-backdrop').remove();
      $('body').removeClass('modal-open').css('padding-right', '');
    }
  },
  methods: {
    async init() {
      try {
        if (this.kind === 'edit') this.initEdit();
        else if (this.kind === 'move') await this.loadTree();
        else if (this.kind === 'access') await this.loadAccess();
        else if (this.kind === 'comment') await this.loadComments();
      } catch (e) {
        this.error = (e && e.message) || '加载失败';
      }
    },
    initEdit() {
      const a = this.row.attributes || {};
      this.form.name = a.name || '';
      this.form.startDate = (a.startDate || '').toString().slice(0, 10);
      this.form.due = (a.due || '').toString().slice(0, 10);
      this.form.description = a.description || '';
    },
    async loadTree() {
      this.loading = true;
      try {
        const url = this.action.folders_tree_url;
        const res = await axios.get(url, { headers: { Accept: 'application/json' } });
        this.folderTree = this.flattenTree(res.data && (res.data.data || res.data));
      } finally {
        this.loading = false;
      }
    },
    flattenTree(nodes, depth = 0, out = []) {
      (nodes || []).forEach((n) => {
        const f = n.folder || n;
        out.push({ id: f.id, name: `${'　'.repeat(depth)}${f.name}` });
        if (n.children) this.flattenTree(n.children, depth + 1, out);
      });
      return out;
    },
    async loadAccess() {
      this.loading = true;
      try {
        const base = this.action.url;
        const [membersRes, rolesRes] = await Promise.all([
          axios.get(base, { headers: { Accept: 'application/json' } }),
          axios.get(`${base}/user_roles`, { headers: { Accept: 'application/json' } })
        ]);
        const mData = (membersRes.data && (membersRes.data.data || membersRes.data)) || [];
        this.members = mData.map((m) => {
          const attrs = m.attributes || m;
          const user = attrs.user || {};
          return {
            id: user.id,
            name: user.name || attrs.name,
            roleId: attrs.user_role && attrs.user_role.id
          };
        }).filter((m) => m.id);
        const rData = (rolesRes.data && (rolesRes.data.data || rolesRes.data)) || [];
        this.userRoles = rData.map((r) => (r.attributes ? { id: r.id, name: r.attributes.name } : { id: r.id, name: r.name }));
        if (this.userRoles.length && !this.newRoleId) this.newRoleId = String(this.userRoles[0].id);
        // 可指派用户 = 全部用户 - 已指派（由 assignableUsersUrl 提供；缺失则留空）
      } catch (e) {
        this.error = (e && e.message) || '成员列表加载失败';
      } finally {
        this.loading = false;
      }
    },
    async changeRole(member, ev) {
      this.busy = true;
      this.error = '';
      try {
        await axios.put(this.action.url, {
          user_assignment: { user_id: member.id, user_role_id: ev.target.value }
        });
        member.roleId = ev.target.value;
      } catch (e) {
        this.error = (e && e.message) || '角色更新失败';
      } finally {
        this.busy = false;
      }
    },
    async removeMember(member) {
      this.busy = true;
      this.error = '';
      try {
        await axios.delete(this.action.url, {
          data: { user_assignment: { user_id: member.id } }
        });
        this.members = this.members.filter((m) => m.id !== member.id);
      } catch (e) {
        this.error = (e && e.message) || '移除成员失败';
      } finally {
        this.busy = false;
      }
    },
    async addMember() {
      if (!this.newUserId) return;
      this.busy = true;
      this.error = '';
      try {
        await axios.post(this.action.url, {
          user_assignment: { user_id: Number(this.newUserId), user_role_id: Number(this.newRoleId) }
        });
        const u = this.assignableUsers.find((x) => String(x.id) === this.newUserId);
        this.members.push({ id: Number(this.newUserId), name: u ? u.name : '', roleId: Number(this.newRoleId) });
        this.newUserId = '';
      } catch (e) {
        this.error = (e && e.message) || '添加成员失败';
      } finally {
        this.busy = false;
      }
    },
    async loadComments() {
      this.loading = true;
      try {
        const res = await axios.get(this.action.url, { headers: { Accept: 'application/json' } });
        const d = res.data || {};
        this.commentsHtml = d.comments || '';
        this.commentAddable = !!d.comment_addable;
      } catch (e) {
        this.error = (e && e.message) || '评论加载失败';
      } finally {
        this.loading = false;
      }
    },
    async postComment() {
      if (!this.newComment.trim()) return;
      this.busy = true;
      this.error = '';
      try {
        await axios.post(this.action.url, { comment: { message: this.newComment } });
        this.newComment = '';
        await this.loadComments();
      } catch (e) {
        this.error = (e && e.message) || '评论发送失败';
      } finally {
        this.busy = false;
      }
    },
    async onPrimary() {
      if (this.kind === 'edit') return this.submitEdit();
      if (this.kind === 'move') return this.submitMove();
      if (this.kind === 'archive') return this.submitArchive();
      if (this.kind === 'delete') return this.submitDelete();
      if (this.kind === 'export') return this.submitExport();
    },
    async submitEdit() {
      this.busy = true;
      this.error = '';
      try {
        const payload = this.isFolder
          ? { project_folder: { name: this.form.name } }
          : {
              project: {
                name: this.form.name,
                start_date: this.form.startDate || null,
                due_date: this.form.due || null,
                description: this.form.description
              }
            };
        await axios.patch(this.action.url, payload);
        this.closeModal();
      } catch (e) {
        this.error = (e && e.message) || '保存失败';
      } finally {
        this.busy = false;
      }
    },
    async submitMove() {
      this.busy = true;
      this.error = '';
      try {
        await axios.post(this.action.url, {
          destination_folder_id: this.selectedFolder,
          movables: [{ id: this.row.id, type: this.isFolder ? 'project_folders' : 'projects' }]
        });
        this.closeModal();
      } catch (e) {
        this.error = (e && e.message) || '移动失败';
      } finally {
        this.busy = false;
      }
    },
    async submitArchive() {
      this.busy = true;
      this.error = '';
      try {
        const bodyKey = this.action.body_key || 'project_ids';
        await axios.post(this.action.url, { [bodyKey]: [this.row.id] });
        this.closeModal();
      } catch (e) {
        this.error = (e && e.message) || '归档失败';
      } finally {
        this.busy = false;
      }
    },
    async submitDelete() {
      this.busy = true;
      this.error = '';
      try {
        const bodyKey = this.action.body_key || 'project_folder_ids';
        await axios.post(this.action.url, { [bodyKey]: [this.row.id] });
        this.closeModal();
      } catch (e) {
        this.error = (e && e.message) || '删除失败';
      } finally {
        this.busy = false;
      }
    },
    async submitExport() {
      this.busy = true;
      this.error = '';
      try {
        await axios.post(this.action.url, { project_ids: [this.row.id] });
        this.closeModal();
      } catch (e) {
        this.error = (e && e.message) || '导出失败（服务端异常，请联系管理员）';
      } finally {
        this.busy = false;
      }
    },
    closeModal() {
      const $ = window.jQuery || window.$;
      if ($ && this.$refs.modal) $(this.$refs.modal).modal('hide');
      else this.$emit('closed');
    }
  }
};
</script>
