<template>
  <!--
    ELN 卡片视图的卡面（挂在宿主 shared/datatable 的 #card 具名插槽上）。

    ⚠ 为什么不复用宿主 `host/projects/card.vue`：它读的是**原生行形状**
      （`params.urls.show` / `params.created_at` / `params.users`），而 ELN grid 行是
      `detailUrl` / `createdAt` / `members` —— 直接复用会在 `params.urls.show` 上抛
      `TypeError: ... reading 'show'`，卡片渲染成空白（实测）。故按 ELN 行形状自绘，
      版式沿用旧版（V1 `ELN系统-Vue3/src/views/ProjectList.vue` 的 .proj-card）。

    ⚠ 行集合含**两类行**（项目行 ∪ 文件夹行，spec SCN-PROJ-LIST-7）：
      切到卡片视图后文件夹行必须有卡面，否则用户会觉得「数据凭空少了一半」。
  -->
  <div class="eln-card" :class="{ 'eln-card--folder': row.folder }" :data-e2e="cardDomId">
    <!-- 文件夹行：名称进层级 + PF<id> + 「x 个项目 | y 个文件夹」 -->
    <template v-if="row.folder">
      <div class="ec-top">
        <a class="ec-link" :href="row.drillUrl" :data-e2e="cardDomId + '-name'">
          <i class="sn-icon sn-icon-folder"></i>{{ row.name }}
        </a>
      </div>
      <div class="ec-meta">
        <span class="ec-code">{{ row.code || '—' }}</span>
        <span v-if="row.folderInfo" class="ec-info">{{ row.folderInfo }}</span>
      </div>
    </template>

    <!-- 项目行：名称下钻 + 状态 + PR<id> + 负责人 + 截止 + 实验进度 -->
    <template v-else>
      <div class="ec-top">
        <a class="ec-link" :href="row.detailUrl" :data-e2e="cardDomId + '-name'">{{ row.name }}</a>
      </div>
      <div class="ec-meta">
        <span v-if="status.label" class="ec-dot" :style="{ backgroundColor: status.color }"></span>
        <span v-if="status.label" class="ec-status" :style="{ color: status.color }">{{ status.label }}</span>
        <span class="ec-code">{{ row.code || '—' }}</span>
      </div>
      <div v-if="owner" class="ec-row">
        <span class="ec-avatar" :style="avatarStyle(owner.color)">{{ owner.initial }}</span>
        <span class="ec-owner">{{ owner.name }}</span>
      </div>
      <div class="ec-row">
        <span class="ec-label">截止</span>
        <span class="ec-num">{{ row.due || '—' }}</span>
      </div>
      <div class="ec-progress">
        <span class="ec-ptext">{{ completed }}/{{ total }} 个实验</span>
        <div class="ec-track">
          <div class="ec-fill" :style="{ width: pct + '%' }"></div>
        </div>
      </div>
    </template>
  </div>
</template>

<script>
// 状态口径与头像配色都走共享模块（表格/卡片同一份真源）
import { elnStatus } from './status_map';
import { avatarStyle } from './avatar_palette';

export default {
  name: 'ElnProjectCard',
  props: {
    params: { required: true }
  },
  computed: {
    row() {
      return this.params || {};
    },
    status() {
      return elnStatus(this.row.status);
    },
    owner() {
      const o = this.row.owner;
      return o && o.name ? o : null;
    },
    completed() {
      return Number(this.row.completed || 0);
    },
    total() {
      return Number(this.row.total || 0);
    },
    // 与表格列同款：0/0 时给最小 3%（原生 CounterRenderer 口径），不是 0 宽度
    pct() {
      if (this.completed === 0 || this.total === 0) return 3;
      return Math.round((this.completed / this.total) * 100);
    },
    // 与行 DOM id 同款判别（folder-<id> / row-<id>），避免两类行 id 相撞
    cardDomId() {
      return (this.row.folder ? 'folder-' : 'row-') + this.row.id;
    }
  },
  methods: {
    avatarStyle
  }
};
</script>

<style scoped>
/* 版式沿用旧版 .proj-card：白底 / 圆角 12 / 细边 / 纵向 flex gap 10 */
.eln-card {
  background: #ffffff;
  border: 1px solid #eaecf0;
  border-radius: 12px;
  box-shadow: 0 1px 2px rgba(16, 24, 40, 0.05);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  min-width: 0;
}
.eln-card:hover {
  border-color: #3b99fd;
}
.ec-top {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.ec-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #101828;
  font-weight: 500;
  text-decoration: none;
}
.ec-link:hover {
  color: #3b99fd;
}
.eln-card--folder .ec-link i {
  color: #3b99fd;
  flex-shrink: 0;
}
.ec-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: #475467;
}
.ec-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
.ec-status {
  font-size: 12px;
}
.ec-code,
.ec-num {
  font-size: 12px;
  color: #667085;
}
.ec-info {
  font-size: 12px;
  color: #98a2b3;
}
.ec-row {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: #101828;
  min-width: 0;
}
.ec-label {
  width: 52px;
  flex-shrink: 0;
  font-size: 12px;
  color: #667085;
}
.ec-owner {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
/* 头像：与表格列同一调色板（浅底深字，24px 圆） */
.ec-avatar {
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
/* 进度：与表格「已完成实验」列同款（轨道 + 填充） */
.ec-progress {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.ec-ptext {
  font-size: 11px;
  color: #667085;
  line-height: 1;
}
.ec-track {
  width: 100%;
  height: 4px;
  border-radius: 2px;
  background: #eaecf0;
  overflow: hidden;
}
.ec-fill {
  height: 100%;
  border-radius: 2px;
  background: #3b99fd;
}
</style>
