<template>
  <!-- 项目列表（画布 4:67 / 4:306）：内容区 gap18 padding28，10 列表格 + 原生交互 -->
  <div class="proj-list">
    <PageHeader
      title="项目"
      :subtitle="subtitle"
      show-navigator
      @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
    >
      <!-- 工作台入口（OPEN-WB-7）
           宿主左菜单那 11 项（/dashboard /insights /projects /repositories …）
           里一个 /eln_workbench 都没有，工作台此前只能直输 URL 进。
           落点由 payload 下发到 ui.workbenchUrl（铁律：前端不写死宿主路由），
           空 = 整颗按钮不渲染，不是渲染出来再置灰。
           用 <a> 不用 <button>：它是一次真实跳转，不是弹窗/本地动作。 -->
      <template v-if="ui.workbenchUrl" #right>
        <a
          class="eln-btn-ghost"
          :href="ui.workbenchUrl"
          data-e2e="tb-goto-workbench"
        ><AppIcon name="layout" :size="15" />工作台</a>
      </template>
    </PageHeader>

    <!-- 工具栏三段式（原生 toolbar.vue）：左按钮 / 中下拉 / 右图标钮
         7 个控件的真机行为（与原生 projects 页同源，不另造口径）：
           新建项目   —— POST 原生 /projects（仅单位管理员 + 非归档态可见）
           新建文件夹 —— POST 原生 /project_folders
           表格/卡片  —— 前端切换渲染，不回服务端
           活动/归档  —— 原生 view_mode 参数，切了重拉列表
           搜索       —— 原生 search 参数，debounce 300ms 后重拉
           筛选       —— filters[...] 键名对齐 Lists::ProjectsService
           列管理     —— 纯前端列显隐
         原型独立跑（没注入 listUrl/createUrls）时全部退化为只改本地状态，不发请求。 -->
    <div class="toolbar">
      <div class="tb-left">
        <button
          v-if="showCreateProject"
          class="eln-btn-primary"
          data-e2e="tb-create-project"
          @click="openNewProject"
        ><AppIcon name="plus" :size="15" />新建项目</button>
        <button
          v-if="ui.canCreateFolder"
          class="eln-btn-ghost"
          data-e2e="tb-create-folder"
          @click="openNewFolder"
        ><AppIcon name="folder-plus" :size="15" />新建文件夹</button>
      </div>
      <div class="tb-center">
        <div class="tb-dropdown-wrap">
          <button class="tb-dropdown" data-e2e="tb-view-render" @click.stop="toggleMenu('render')">
            <AppIcon :name="ui.viewRender === 'cards' ? 'layout' : 'columns'" :size="14" />
            {{ viewRenderLabel }}
            <AppIcon name="chevron-down" :size="13" />
          </button>
          <div v-if="menu === 'render'" class="tb-menu" data-e2e="tb-menu-render">
            <button
              v-for="r in viewRenders"
              :key="r.value"
              class="tb-menu-item"
              :class="{ on: ui.viewRender === r.value }"
              @click="pickRender(r.value)"
            >{{ r.label }}</button>
          </div>
        </div>
        <div class="tb-dropdown-wrap">
          <button class="tb-dropdown" data-e2e="tb-view-mode" @click.stop="toggleMenu('mode')">
            {{ viewModeLabel }}
            <AppIcon name="chevron-down" :size="13" />
          </button>
          <div v-if="menu === 'mode'" class="tb-menu" data-e2e="tb-menu-mode">
            <button
              v-for="m in viewModes"
              :key="m.value"
              class="tb-menu-item"
              :class="{ on: ui.viewMode === m.value }"
              @click="pickMode(m.value)"
            >{{ m.label }}</button>
          </div>
        </div>
      </div>
      <div class="tb-right">
        <div class="search-wrap">
          <button class="eln-icon-btn" title="搜索" data-e2e="tb-search" @click="toggleSearch">
            <AppIcon name="search" :size="15" />
          </button>
          <input
            v-if="ui.searchOpen"
            v-model="ui.query"
            class="search-input"
            data-e2e="tb-search-input"
            placeholder="搜索项目…"
            @input="onSearchInput"
          />
        </div>
        <button class="eln-icon-btn" title="筛选" data-e2e="tb-filter" @click="openFilter">
          <AppIcon name="filter" :size="15" />
        </button>
        <div class="tb-dropdown-wrap">
          <button class="eln-icon-btn" title="列管理" data-e2e="tb-columns" @click.stop="toggleMenu('cols')">
            <AppIcon name="columns" :size="15" />
          </button>
          <!-- ⚠ 列管理菜单必须 @click.stop：勾完一列菜单要**保持打开**好继续勾下一列，
               而上面的 onDocClick 会把任意点击都当成「收起下拉」——不 stop 就点一次关一次。 -->
          <div v-if="menu === 'cols'" class="tb-menu cols-menu" data-e2e="tb-menu-cols" @click.stop>
            <!-- V1.34 对齐原生 Manage columns 弹窗（shared/datatable/modals/columns.vue）：
                 每列 = 显隐勾选 + 图钉，**每列独立**钉住 / 取消，可同时钉多列。
                 渲染顺序 = 钉住组 → pinnedSeparator 分隔线 → 未钉组（原生同款分组：
                 线以上是横向滚动不动的钉区，线以下跟着滚）。 -->
            <template v-for="item in columnMenuItems" :key="item.key">
              <div v-if="item.separator" class="cols-sep" data-e2e="tb-cols-sep"></div>
              <label
                v-else
                class="tb-menu-item cols-item"
                :class="{ disabled: item.locked }"
              >
                <input
                  type="checkbox"
                  :checked="ui.columnVisibility[item.key]"
                  :disabled="item.locked"
                  @change="toggleColumn(item.key)"
                />
                <span class="cols-item-label">{{ item.label }}</span>
                <!-- 恒钉列（check）不给图钉：它取消不了，给了就是个点了没反应的死按钮 -->
                <span
                  v-if="item.pinnable"
                  class="col-pin-btn"
                  :class="{ on: item.pinned }"
                  :data-e2e="'tb-cols-pin-' + item.key"
                  :title="item.pinned ? '取消钉住' : '钉住该列'"
                  @click.prevent="togglePinned(item.key)"
                ><AppIcon name="pin" :size="13" /></span>
              </label>
            </template>
            <!-- 列宽调乱后要能一键回来（原生 ag-grid 有 reset column state，我们同款） -->
            <button
              class="tb-menu-item cols-reset"
              data-e2e="tb-cols-reset"
              title="把所有列宽恢复默认值"
              @click="onResetWidths"
            ><AppIcon name="restore" :size="13" />重置列宽</button>
          </div>
        </div>
      </div>
    </div>

    <!-- 筛选项取数失败：下拉拿不到数据不能静默显示成「没数据」，必须显式说清楚是哪几项 -->
    <div
      v-if="ui.filterOptionErrors && ui.filterOptionErrors.length"
      class="tb-hint err"
      data-e2e="tb-option-errors"
    >筛选项不可用：{{ ui.filterOptionErrors.join('、') }}（对应下拉为空，非无数据）</div>

    <!-- 刷新态 / 失败提示：按钮点了没反应是最难查的一类缺陷，必须把结果显式渲出来 -->
    <div v-if="ui.listError" class="tb-hint err" data-e2e="tb-error">{{ ui.listError }}</div>
    <div v-else-if="ui.listLoading" class="tb-hint" data-e2e="tb-loading">加载中…</div>

    <!-- V1.32 文件夹层级面包屑（spec SCN-PROJ-LIST-7 第 4 条）
         「进入文件夹层级 + 提供返回上一层的入口」。
         ⚠ 整块在**顶层不渲染**（folderNav.upUrl 为空 ⇒ v-if 为假）—— 显式留白，
           而不是渲染一个点了回原地的死入口。
         ⚠ 全部链接来自 payload（crumb.url / upUrl），前端**不拼**宿主路由
           （铁律：路径词汇表只一套，禁编 /eln_ 之类的假路由）。 -->
    <nav v-if="folderCrumbs.length" class="folder-crumbs" data-e2e="folder-crumbs">
      <a class="fc-link" :href="rootUrl" data-e2e="fc-up-root">全部项目</a>
      <template v-for="(c, i) in folderCrumbs" :key="'fc-' + c.id">
        <span class="fc-sep">/</span>
        <a
          class="fc-link"
          :class="{ current: i === folderCrumbs.length - 1 }"
          :href="c.url"
          :data-e2e="'fc-' + c.code"
        >{{ c.name }}</a>
      </template>
      <span v-if="ui.folderNav.upUrl" class="fc-spacer"></span>
      <a v-if="ui.folderNav.upUrl" class="fc-up" :href="ui.folderNav.upUrl" data-e2e="fc-up">
        返回上一层
      </a>
    </nav>

    <!-- 表格卡片（白底 圆角12 阴影） -->
    <div v-if="ui.viewRender === 'table'" class="table-card">
      <!-- 🔴 横向滚动的落点：列宽走 CSS 变量挂在这个容器上（表头/数据行共用一条规则） -->
      <div class="table-scroll" ref="tableScrollEl" data-e2e="table-scroll">
        <!-- 表头行：#F5F5F7 高40 圆角6 -->
        <div class="thead">
          <div v-if="ui.columnVisibility.check" class="th col-check" v-bind="pinCell('check')">
            <span
              class="checkbox"
              :class="{ checked: allSelected }"
              @click="toggleAll"
            ></span>
          </div>
          <div v-if="ui.columnVisibility.star" class="th col-star" v-bind="pinCell('star')">★</div>
          <!-- 可排序列头（原生同款交互）：点一下升序 → 再点降序 → 第三下取消。
               column 值是原生 Lists::ProjectsService 的 key，不是我们的列名。 -->
          <div
            v-if="ui.columnVisibility.name"
            class="th col-name sortable" v-bind="pinCell('name')"
            :class="{ active: ui.sort.column === 'name' }"
            data-e2e="sort-name"
            @click="toggleSort('name')"
          >
            <span>项目名称</span><span class="sort-arrow" v-text="sortMark('name')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'name' }"
              :data-e2e="'rz-name'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('name', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.id"
            class="th col-id sortable" v-bind="pinCell('id')"
            :class="{ active: ui.sort.column === 'code' }"
            data-e2e="sort-code"
            @click="toggleSort('code')"
          >
            <span>ID</span><span class="sort-arrow" v-text="sortMark('code')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'id' }"
              :data-e2e="'rz-id'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('id', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.status"
            class="th col-status sortable" v-bind="pinCell('status')"
            :class="{ active: ui.sort.column === 'status' }"
            data-e2e="sort-status"
            @click="toggleSort('status')"
          >
            <span>状态</span><span class="sort-arrow" v-text="sortMark('status')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'status' }"
              :data-e2e="'rz-status'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('status', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.start"
            class="th col-start sortable" v-bind="pinCell('start')"
            :class="{ active: ui.sort.column === 'start_date' }"
            data-e2e="sort-start"
            @click="toggleSort('start_date')"
          >
            <span>开始日期</span><span class="sort-arrow" v-text="sortMark('start_date')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'start' }"
              :data-e2e="'rz-start'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('start', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.due"
            class="th col-due sortable" v-bind="pinCell('due')"
            :class="{ active: ui.sort.column === 'due_date' }"
            data-e2e="sort-due"
            @click="toggleSort('due_date')"
          >
            <span>截止日期</span><span class="sort-arrow" v-text="sortMark('due_date')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'due' }"
              :data-e2e="'rz-due'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('due', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.owner"
            class="th col-owner sortable" v-bind="pinCell('owner')"
            :class="{ active: ui.sort.column === 'supervised_by' }"
            data-e2e="sort-owner"
            @click="toggleSort('supervised_by')"
          >
            <span>项目负责人</span><span class="sort-arrow" v-text="sortMark('supervised_by')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'owner' }"
              :data-e2e="'rz-owner'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('owner', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.exp"
            class="th col-exp sortable" v-bind="pinCell('exp')"
            :class="{ active: ui.sort.column === 'completed_experiments' }"
            data-e2e="sort-exp"
            @click="toggleSort('completed_experiments')"
          >
            <span>已完成实验</span><span class="sort-arrow" v-text="sortMark('completed_experiments')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'exp' }"
              :data-e2e="'rz-exp'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('exp', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.tasks"
            class="th col-tasks sortable" v-bind="pinCell('tasks')"
            :class="{ active: ui.sort.column === 'completed_tasks' }"
            data-e2e="sort-tasks"
            @click="toggleSort('completed_tasks')"
          >
            <span>已完成任务</span><span class="sort-arrow" v-text="sortMark('completed_tasks')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'tasks' }"
              :data-e2e="'rz-tasks'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('tasks', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.users"
            class="th col-users sortable" v-bind="pinCell('users')"
            :class="{ active: ui.sort.column === 'users' }"
            data-e2e="sort-users"
            @click="toggleSort('users')"
          >
            <span>访问权限</span><span class="sort-arrow" v-text="sortMark('users')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'users' }"
              :data-e2e="'rz-users'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('users', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.comments"
            class="th col-comments sortable" v-bind="pinCell('comments')"
            :class="{ active: ui.sort.column === 'comments' }"
            data-e2e="sort-comments"
            @click="toggleSort('comments')"
          >
            <span>评论</span><span class="sort-arrow" v-text="sortMark('comments')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'comments' }"
              :data-e2e="'rz-comments'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('comments', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.desc"
            class="th col-desc sortable" v-bind="pinCell('desc')"
            :class="{ active: ui.sort.column === 'description' }"
            data-e2e="sort-desc"
            @click="toggleSort('description')"
          >
            <span>描述</span><span class="sort-arrow" v-text="sortMark('description')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'desc' }"
              :data-e2e="'rz-desc'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('desc', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.created"
            class="th col-created sortable" v-bind="pinCell('created')"
            :class="{ active: ui.sort.column === 'created_at' }"
            data-e2e="sort-created"
            @click="toggleSort('created_at')"
          >
            <span>创建时间</span><span class="sort-arrow" v-text="sortMark('created_at')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'created' }"
              :data-e2e="'rz-created'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('created', $event)"
              @click.stop
            ></span>
          </div>
          <div
            v-if="ui.columnVisibility.updated"
            class="th col-updated sortable" v-bind="pinCell('updated')"
            :class="{ active: ui.sort.column === 'updated_at' }"
            data-e2e="sort-updated"
            @click="toggleSort('updated_at')"
          >
            <span>更新时间</span><span class="sort-arrow" v-text="sortMark('updated_at')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'updated' }"
              :data-e2e="'rz-updated'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('updated', $event)"
              @click.stop
            ></span>
          </div>
          <!-- 归档日期：原生只在 archived 视图 push 这一列（活动项目没有归档日期） -->
          <div
            v-if="ui.columnVisibility.archived && ui.viewMode === 'archived'"
            class="th col-archived sortable" v-bind="pinCell('archived')"
            :class="{ active: ui.sort.column === 'archived_on' }"
            data-e2e="sort-archived"
            @click="toggleSort('archived_on')"
          >
            <span>归档日期</span><span class="sort-arrow" v-text="sortMark('archived_on')"></span>
            <span
              class="col-resize-handle"
              :class="{ active: dragKey === 'archived' }"
              :data-e2e="'rz-archived'"
              title="拖拽调整列宽（按住 Shift 同时调整相邻列）"
              @pointerdown="onDown('archived', $event)"
              @click.stop
            ></span>
          </div>
          <div v-if="ui.columnVisibility.action" class="th col-action" v-bind="pinCell('action')"></div>
        </div>
        <!-- 数据行：高48
             🔴 下钻的两条非鼠标路径都挂在这里：
                 · 右键 → 行操作菜单 → 「打开项目详情」
                 · 键盘 Enter → 直接下钻（focusRow 由 ↑↓ 维护，见 script 段）

             V1.32：本数组是**行集合**（项目行 ∪ 文件夹行），按 `row.folder` 分流。
             ⚠ `:key` 用 `rowKey(row)`（类型判别符 + 数字主键）而**不是**裸 `row.id` ——
               projects 与 project_folders 是两张表，id 会撞（项目 7 与文件夹 7 同时存在），
               裸 id 当 key 会让 Vue 复用到错误行（表现为「点了 A 高亮 B」）。
               注意它**不是**用 `code` 当 key（code 是显示值，见 SCN-PROJ-LIST-8 第 4 条）。 -->
        <div
          v-for="(p, i) in projects"
          :key="rowKey(p)"
          class="trow"
          :class="{ focused: focusIndex === i, 'is-folder': p.folder }"
          :data-e2e="rowDomId(p)"
          tabindex="0"
          @contextmenu.prevent="openMenu($event, p)"
          @keydown="onRowKeydown($event, i)"
        >
          <!-- 勾选：只对**项目行**渲染复选框。
               ⚠ 这是**有意收窄**，已登记为待办（spec SCN-PROJ-LIST-10 的"批量操作条按选中集合
                 向后端求取"尚未落地）：现有批量条三颗按钮（移动/归档/导出）打的 body 全是
                 `project_ids`，把文件夹 id 混进去 = 发一个服务端会静默丢弃的请求，用户点了没反应。
                 宁可**显式不提供**，也不给一个「勾了但没用」的入口。 -->
          <div v-if="ui.columnVisibility.check" class="td col-check" v-bind="pinCell('check')">
            <span
              v-if="!p.folder"
              class="checkbox"
              :class="{ checked: ui.selectedProjectIds.includes(p.id) }"
              @click="toggleProjectSelection(p.id)"
            ></span>
          </div>
          <div v-if="ui.columnVisibility.star" class="td col-star" v-bind="pinCell('star')">
            <span
              v-if="!p.folder"
              class="star"
              :class="{ on: p.starred }"
              @click="p.starred = !p.starred"
            >★</span>
          </div>
          <!-- 名称：项目行 → 下钻项目详情；文件夹行 → 进入该文件夹层级（drillUrl）
               + 第二行「x 个项目 | y 个文件夹」（原生 folder_info 同位置、同文案） -->
          <div class="td col-name" v-bind="pinCell('name')">
            <template v-if="p.folder">
              <a class="proj-link folder-link" :href="p.drillUrl" :data-e2e="rowDomId(p) + '-name'">
                <AppIcon name="folder" :size="15" />{{ p.name }}
              </a>
              <span v-if="p.folderInfo" class="folder-info" :data-e2e="rowDomId(p) + '-info'">
                {{ p.folderInfo }}
              </span>
            </template>
            <router-link v-else :to="drillTo(p, 'project')" class="proj-link">{{ p.name }}</router-link>
          </div>
          <!-- ID 列：**显示 `code`**（`PR<id>` / `PF<id>`），不是数字主键 ——
               spec SCN-PROJ-LIST-8。数字主键仍用于下钻/选中/请求参数，两者不互换。 -->
          <div v-if="ui.columnVisibility.id" class="td col-id num" v-bind="pinCell('id')" :data-e2e="rowDomId(p) + '-code'">
            {{ p.code || '—' }}
          </div>
          <div v-if="ui.columnVisibility.status" class="td col-status" v-bind="pinCell('status')">
            <template v-if="!p.folder">
              <span class="status-dot" :style="{ background: statusColor[p.status] }"></span>
              <span class="status-text" :style="{ color: statusColor[p.status] }">{{ statusLabel[p.status] }}</span>
            </template>
          </div>
          <div v-if="ui.columnVisibility.start" class="td col-start num" v-bind="pinCell('start')">{{ p.folder ? '' : (p.startDate || '—') }}</div>
          <div v-if="ui.columnVisibility.due" class="td col-due num" v-bind="pinCell('due')">{{ p.folder ? '' : (p.due || '—') }}</div>
          <div v-if="ui.columnVisibility.owner" class="td col-owner" v-bind="pinCell('owner')">
            <template v-if="!p.folder">
              <span class="avatar sm" :style="avatarStyle(p.owner.color)">{{ p.owner.initial }}</span>
              <span>{{ p.owner.name }}</span>
            </template>
          </div>
          <div v-if="ui.columnVisibility.exp" class="td col-exp" v-bind="pinCell('exp')">
            <div v-if="!p.folder" class="exp-cell">
              <span class="exp-text">{{ p.completed }}/{{ p.total }} 个实验</span>
              <div class="exp-track">
                <div
                  class="exp-fill"
                  :style="{ width: expWidth(p) + 'px' }"
                ></div>
              </div>
            </div>
          </div>
          <!-- 已完成任务：与实验列同款进度条，口径 = 非归档任务里处于终态的数量 -->
          <div v-if="ui.columnVisibility.tasks" class="td col-tasks" v-bind="pinCell('tasks')">
            <div v-if="!p.folder" class="exp-cell">
              <span class="exp-text">{{ p.tasksCompleted ?? 0 }}/{{ p.tasksTotal ?? 0 }} 个任务</span>
              <div class="exp-track">
                <div
                  class="exp-fill"
                  :style="{ width: taskWidth(p) + 'px' }"
                ></div>
              </div>
            </div>
          </div>
          <div v-if="ui.columnVisibility.users" class="td col-users" v-bind="pinCell('users')">
            <div v-if="!p.folder" class="avatar-group">
              <span
                v-for="(m, i) in p.members.slice(0, 3)"
                :key="i"
                class="avatar sm"
                :class="{ group: m.kind === 'group' }"
                :style="avatarStyle(m.color)"
                :title="m.name"
              >
                <svg v-if="m.kind === 'group'" class="group-icon" viewBox="0 0 24 24" width="13" height="13" aria-hidden="true">
                  <path fill="currentColor" d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5s-3 1.34-3 3 1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
                </svg>
                <template v-else>{{ m.initial }}</template>
              </span>
              <span v-if="p.extra > 0" class="avatar more">+{{ p.extra }}</span>
            </div>
          </div>
          <div v-if="ui.columnVisibility.comments" class="td col-comments num" v-bind="pinCell('comments')">
            {{ p.folder ? '' : (p.commentsCount ?? 0) }}
          </div>
          <div
            v-if="ui.columnVisibility.desc"
            class="td col-desc" v-bind="pinCell('desc')"
            :title="p.folder ? '' : (p.description || '')"
            data-e2e="cell-desc"
          >{{ p.folder ? '' : (p.description || '—') }}</div>
          <div v-if="ui.columnVisibility.created" class="td col-created num" v-bind="pinCell('created')">{{ p.folder ? '' : (p.createdAt || '—') }}</div>
          <div v-if="ui.columnVisibility.updated" class="td col-updated num" v-bind="pinCell('updated')">{{ p.folder ? '' : (p.updatedAt || '—') }}</div>
          <div
            v-if="ui.columnVisibility.archived && ui.viewMode === 'archived'"
            class="td col-archived num" v-bind="pinCell('archived')"
          >{{ p.folder ? (p.archivedOn || '') : (p.archivedOn || '—') }}</div>
          <div v-if="ui.columnVisibility.action" class="td col-action" v-bind="pinCell('action')">
            <button class="row-more" @click.stop="openMenu($event, p)">
              <AppIcon name="more" :size="16" />
            </button>
          </div>
        </div>
        <div v-if="projects.length === 0" class="empty-row" data-e2e="tb-empty">
          {{ ui.folderId ? '这个文件夹是空的' : '没有符合条件的项目' }}
        </div>
      </div>

      <!-- V1.31 分页信息条
           ⚠ 这是**有意偏离原生**：原生表格是 scrollMode="infinite"（滚动到底自动加载、
           **没有**分页底栏）。分页属本 addon 已登记的自研增量
           （spec REQ-PROJ-LIST「自研增量必须显式登记」表），复刻原生时
           **不得**以「原生没有」为由删掉，也不得加「无限滚动」开关（V1.30 已裁定不保留）。
           落点沿用原生 datatable 分页条的位置：**表格卡片内、滚动区之下** ——
           放在 .table-scroll 外面，列横向滚动时它不跟着跑。 -->
      <div class="table-pager" data-e2e="tb-pager">
        <div class="tp-left">
          <span class="tp-label">显示：</span>
          <select
            class="tp-select"
            data-e2e="tb-per-page"
            :value="String(ui.perPage)"
            @change="onPerPageChange"
          >
            <option v-for="n in perPageOptions" :key="n" :value="String(n)">{{ perPageLabel(n) }}</option>
          </select>
          <span class="tp-count" data-e2e="tb-count">{{ countText }}</span>
        </div>
        <!-- 总条数未超过一页时不渲染页码控件（spec SCN-PROJ-LIST-13 第 5 条）；
             左侧的档位与计数仍在 —— 用户仍要能改档位、也要能看到条数。 -->
        <div v-if="showPager" class="tp-right" data-e2e="tb-pager-nav">
          <button
            class="tp-btn"
            data-e2e="tb-prev"
            :disabled="ui.page <= 1"
            @click="gotoPage(ui.page - 1)"
          >上一页</button>
          <button
            v-for="p in pageNumbers"
            :key="p"
            class="tp-btn page"
            :class="{ on: p === ui.page, gap: p === '…' }"
            :disabled="p === '…'"
            :data-e2e="'tb-page-' + p"
            @click="gotoPage(p)"
          >{{ p }}</button>
          <button
            class="tp-btn"
            data-e2e="tb-next"
            :disabled="ui.page >= totalPages"
            @click="gotoPage(ui.page + 1)"
          >下一页</button>
        </div>
      </div>
    </div>

    <!-- 卡片视图（原生 viewRenders=cards）：同一份数据，另一种排布。
         V1.32：行集合里的文件夹行也要有卡片 —— 否则用户切到卡片视图后文件夹会
         **凭空消失**（同一份行集合换个排布就少了行，是最容易被当成"数据丢了"的那类现象）。 -->
    <div v-else class="cards">
      <div v-for="p in projects" :key="rowKey(p)" class="proj-card" :class="{ 'folder-card': p.folder }">
        <template v-if="p.folder">
          <div class="pc-top">
            <a class="proj-link folder-link" :href="p.drillUrl" :data-e2e="rowDomId(p) + '-name'">
              <AppIcon name="folder" :size="15" />{{ p.name }}
            </a>
            <button class="row-more" @click.stop="openMenu($event, p)"><AppIcon name="more" :size="16" /></button>
          </div>
          <div class="pc-meta">
            <span class="num" :data-e2e="rowDomId(p) + '-code'">{{ p.code || '—' }}</span>
            <span v-if="p.folderInfo" class="folder-info">{{ p.folderInfo }}</span>
          </div>
        </template>
        <template v-else>
          <div class="pc-top">
            <span
              class="star"
              :class="{ on: p.starred }"
              @click="p.starred = !p.starred"
            >★</span>
            <router-link :to="drillTo(p, 'project')" class="proj-link">{{ p.name }}</router-link>
            <button class="row-more" @click.stop="openMenu($event, p)"><AppIcon name="more" :size="16" /></button>
          </div>
          <div class="pc-meta">
            <span class="status-dot" :style="{ background: statusColor[p.status] }"></span>
            <span class="status-text" :style="{ color: statusColor[p.status] }">{{ statusLabel[p.status] }}</span>
            <span class="num">{{ p.code || p.id }}</span>
          </div>
          <div class="pc-row">
            <span class="pc-label">负责人</span>
            <span class="avatar sm" :style="avatarStyle(p.owner.color)">{{ p.owner.initial }}</span>
            <span>{{ p.owner.name }}</span>
          </div>
          <div class="pc-row">
            <span class="pc-label">截止</span><span class="num">{{ p.due || '—' }}</span>
          </div>
          <div class="exp-cell pc-exp">
            <span class="exp-text">{{ p.completed }}/{{ p.total }} 个实验</span>
            <div class="exp-track" style="width: 100%">
              <div class="exp-fill" :style="{ width: expPct(p) + '%' }"></div>
            </div>
          </div>
        </template>
      </div>
      <div v-if="projects.length === 0" class="empty-row">
        {{ ui.folderId ? '这个文件夹是空的' : '没有符合条件的项目' }}
      </div>
    </div>
  </div>

</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue/dist/vue.esm-bundler.js'
import PageHeader from '../components/PageHeader.vue'
import AppIcon from '../components/AppIcon.vue'
import { projects, statusLabel, avatarPalette } from '../data/mock'
import { drillTo } from '../utils/drill'
import {
  ui,
  openNavigator,
  closeNavigator,
  openNewProject,
  openNewFolder,
  openFilter,
  openRowMenu,
  closeRowMenu,
  toggleProjectSelection,
  clearSelection,
  toggleSearch,
  setQuery,
  setViewRender,
  setViewMode,
  toggleColumn,
  toggleSort,
  // V1.31 分页动作（改档位回第 1 页 + 清选中 + 重拉；翻页同理）
  setPerPage,
  gotoPage,
  // 行菜单 7 项真源接线（2026-10-06）：endpoints 全部由 payload 下发，
  // 这里只拿到「以什么方式落地」与「转发给浮层」的能力。
  rowMenuItems,
  // V1.32：文件夹行的**专属**菜单集合（编辑/移动/删除；不得混入项目行的动作）
  folderRowMenuItems,
  ROW_ACTION_KINDS,
  openRowAction,
  sendForm,
  showToast,
  refreshList,
  // V1.34：钉列（每列独立钉住 / 取消，可多列；变更即持久化到 user_settings）
  togglePinned,
  isPinned,
  // 列集合唯一真源（列序 / 列名 / locked / alwaysPinned）
  COLUMN_DEFS
} from '../store/ui'
import { useColumnResize, COLUMN_WIDTHS } from '../composables/useColumnResize'

/**
 * 按行算「这个菜单该出现哪些项」。
 * 原生口径（Toolbars::ProjectsService）：权限不够的动作**直接不出现**，
 * 不是渲染出来再置灰。所以这里是 filter + push，不是 filter + 渲染。
 *
 * V1.32：两类行的菜单**互不混用**（spec SCN-PROJ-LIST-7 第 6 条）——
 *   项目行 → 打开项目详情 + 7 项原生存量动作；文件夹行 → 打开文件夹 + 编辑/移动/删除。
 */
function menuItemsFor(row) {
  const acts = row && row.actions ? row.actions : {}
  if (row && row.folder) {
    // 「打开文件夹」永远在最前（进入层级是本行的主路径，与项目行的「打开详情」同位）
    return folderRowMenuItems.filter((item) => item.key === 'open' || (acts[item.key] && acts[item.key].enabled))
  }
  const items = [rowMenuItems[0]] // 「打开项目详情」永远在最前（下钻主路径）
  rowMenuItems.slice(1).forEach((item) => {
    const act = acts[item.key]
    if (act && act.enabled) items.push(item)
  })
  return items
}

/**
 * 行的 DOM key / data-e2e 判别符（V1.32）。
 *
 * 🔴 为什么不能用裸 `row.id`：projects 与 project_folders 是**两张表**，
 *   数字主键会撞（项目 7 与文件夹 7 可以同时存在）。裸 id 当 `:key` 会让 Vue
 *   复用错误的 DOM 行（点 A 高亮 B）；当 `data-e2e` 则会让验收脚本的选择器
 *   随机命中两类行中的一类 —— 那是**假绿**，比报错更危险。
 * ⚠ 但它也**不是**用 `code` 当 key（`code` 是显示值，spec SCN-PROJ-LIST-8 第 4 条
 *   明令显示值与数据 id 不得互换）——这里是「类型判别符 + 数字主键」，
 *   判别符来自 `folder` 布尔（原生同名字段），与 `code` 的前缀规则无关。
 */
function rowKey(row) {
  return (row && row.folder ? 'pf-' : 'pr-') + row.id
}
function rowDomId(row) {
  return (row && row.folder ? 'folder-' : 'row-') + row.id
}

/** 可勾选的行 = **只含项目行**（见模板里勾选格那段注释：批量条是项目口径的） */
const selectableRows = computed(() => projects.filter((r) => !r.folder))

// 面包屑：祖先链（根 → 当前），链接全部来自 payload 下发的 url。
const folderCrumbs = computed(() => {
  const nav = ui.folderNav
  const trail = nav && Array.isArray(nav.trail) ? nav.trail : []
  return trail.filter((c) => c && c.url)
})
// 「全部项目」那一颗：回到顶层 —— 直接用 folderNav.upUrl 的同款基址（当前层级为空时
// upUrl 是整页路径；有父级时 upUrl 指向父级，所以顶层入口要单独取）。
// ⚠ 取 current 的 url 去掉 query 得到本页基址，不写死路由字面量。
const rootUrl = computed(() => {
  const cur = ui.folderNav && ui.folderNav.current
  if (cur && cur.url) return String(cur.url).split('?')[0]
  return ui.folderNav && ui.folderNav.upUrl ? String(ui.folderNav.upUrl).split('?')[0] : ''
})

// 列头排序箭头：激活列 ▲/▼，未激活列 hover 时显示 ⇅（原生同款弱提示）
function sortMark(column) {
  if (ui.sort.column !== column) return '⇅'
  return ui.sort.dir === 'asc' ? '▲' : '▼'
}

// ⚠ 兜底常量必须先声明：Vue <script setup> 存在 TDZ，
// 下面任何 computed/函数里用到却写在后面 → 运行期 ReferenceError、组件静默不挂载。
const statusColor = {
  active: 'var(--status-active)',
  notstarted: 'var(--status-notstarted)',
  done: 'var(--status-done)'
}

const viewRenders = [
  { value: 'table', label: '表格视图' },
  { value: 'cards', label: '卡片视图' }
]

const viewModes = [
  { value: 'active', label: '活动状态' },
  { value: 'archived', label: '归档状态' }
]

// 列集合（唯一真源 = store/ui.js 的 COLUMN_DEFS）。
// ⚠ 不要在这里再列一份：钉列归一化（store 里）与钉列偏移（这里）都要列序，
//   两份清单迟早改漏 —— 加列时只改一边，新列会「渲染不出来」或「钉住偏移算错」。
const columnDefs = COLUMN_DEFS

const menu = ref('')

/**
 * 列宽拖拽 + 横向滚动（原生 /projects 的 ag-grid 同款行为，见 composables/useColumnResize.js）
 *   · 宽度以 CSS 变量形式挂在 .table-scroll 上，表头/数据行共用一条规则 → 拖 200 行也不卡
 *   · CSS 变量挂容器而非 :root，避免同页多表格互相污染
 *   · 宽度存 localStorage，刷新保留（原生列宽也是持久的）
 */
const tableScrollEl = ref(null)
const { widths: colWidths, dragKey, onDown, resetWidths, applyVars } = useColumnResize(tableScrollEl)

// ------------------------------------------------------------
// V1.34 钉列（多列独立钉住）—— 复刻原生 ag-grid 的 pinned-left 容器
//
// 原生做法（shared/datatable/table.vue）：钉住列的 columnDef.pinned='left'，
// ag-grid 把它们渲染进独立的 pinned-left 容器 —— 横向滚动时不动，
// 普通列从它下面穿过去；钉住区右缘有一条投影（hideLastPinnedResizeCell 同款视觉）。
//
// 我们是手写 flex 网格，没有 pinned 容器，用两条 CSS 等价复刻：
//   · 钉住列  order:0 + position:sticky  → 归拢在最左且滚动不动；
//   · 未钉列  order:1                    → 整组排到钉住列之后（组内仍是 DOM 序），
//                                          滚动时 z-index 低，从钉区下方穿过。
//     ⚠ order 必须显式给：默认都是 0，不分组就会出现「钉了 status 但它仍在
//        name 后面」这种看起来没生效的假象。
//
// left 偏移 = 行左留白 + Σ(前面各钉住可见列宽 + gap)。
//   ⚠ 必须带上 gap：flex 行有 gap:12px，只累加列宽会让第 2 列起每列左偏 12px，
//     钉住列之间出现叠压 —— 钉一列看不出来，钉三列就明显错位。
//   ⚠ 带上左留白（20px）是为了 sticky 的 left 恰好等于静态位置：
//     否则横向滚动一开始，钉住列会「跳」20px。
//
// 一次算好整张表（computed），pinCell 只做查表：
//   行内 17 列 × 200 行，若每格都重新累加一遍就是 3400 次 O(n) —— 拖拽列宽时掉帧。
// ------------------------------------------------------------
const COL_GAP = 12   // 与 .thead/.trow 的 gap 同步
const ROW_PAD = 20   // 与 .thead/.trow 的 padding: 0 20px 同步

/** 钉住且可见的列（顺序 = 列序）：钉住区的渲染序与偏移都按它 */
const pinnedVisible = computed(() => columnDefs
  .filter((c) => ui.columnVisibility[c.key] && isPinned(c.key))
  .map((c) => c.key))

const pinStyles = computed(() => {
  const keys = pinnedVisible.value
  const map = {}
  let left = ROW_PAD
  keys.forEach((k, i) => {
    map[k] = {
      class: { pin: true, 'pin-last': i === keys.length - 1 },
      style: { position: 'sticky', left: `${left}px`, order: 0 }
    }
    left += (colWidths.value[k] || COLUMN_WIDTHS[k].w) + COL_GAP
  })
  return map
})

/** 未钉列：order 推到钉住组之后。共享同一个常量对象，渲染期不产生垃圾 */
const UNPINNED = { style: { order: 1 } }

/** th / td 的 v-bind 落点（模板里 34 处 v-bind="pinCell('key')" 全读它） */
function pinCell(key) {
  return pinStyles.value[key] || UNPINNED
}

// ------------------------------------------------------------
// 列管理菜单的渲染顺序：钉住组 → 分隔线 → 未钉组
// （原生 modals/columns.vue 的 pinnedSeparator，视觉上就是这条线）
// ------------------------------------------------------------
const columnMenuItems = computed(() => {
  // 分组依据用 isPinned（**不看可见性**）：钉住但暂时隐藏的列仍属钉住组，
  // 否则它会掉到未钉组、图钉显示成未钉 —— 与真实状态相反（第二真源）。
  const items = []
  columnDefs.forEach((c) => {
    if (isPinned(c.key)) items.push({ ...c, pinned: true, pinnable: !c.alwaysPinned })
  })
  if (items.length) items.push({ key: '__pinned_sep__', separator: true })
  columnDefs.forEach((c) => {
    if (!isPinned(c.key)) items.push({ ...c, pinned: false, pinnable: !c.alwaysPinned })
  })
  return items
})

// 键盘焦点行索引（-1 = 无焦点）。只驱动高亮样式与 Enter 落点，不接管页面滚动。
const focusIndex = ref(-1)

/** 列管理菜单里的「重置列宽」：恢复默认并关掉菜单（否则菜单悬在按钮上方挡住反馈） */
function onResetWidths() {
  resetWidths()
  closeMenu()
}

function toggleMenu(name) {
  menu.value = menu.value === name ? '' : name
}

function closeMenu() {
  menu.value = ''
}

// 点页面任意空白处收起下拉（原生 MenuDropdown 同款行为）
function onDocClick() {
  closeMenu()
  closeRowMenu()
  // 点空白处顺带取消键盘焦点，避免 Enter 打在一个"幽灵焦点"上跳到上一行
  focusIndex.value = -1
}
// Esc 兜底：行菜单打开时按 Esc 要能收回去（原生 projects 页同款）
function onDocKeydown(e) {
  if (e.key === 'Escape' && ui.rowMenuOpen) {
    closeRowMenu()
    focusIndex.value = -1
  }
}
// 🔴 全局监听必须在 onMounted 之前注册：onBeforeUnmount 里要 removeEventListener，
//    如果在 onMounted 之后才 add，卸载时那个函数还是 undefined → 解绑失效 → 内存泄漏。
//    顺序：addEventListener（模块级 / onMounted 前）→ 卸载时 remove。
// ⚠ onRowMenuAction 必须**先定义**再注册（Vue script setup 有 TDZ）：
//   定义写在注册之后 → 模块求值时该函数还是未初始化的 const → ReferenceError →
//   组件静默不挂载。顺序一旦调换就炸，且报错离现场很远。
function onRowMenuAction(evt) {
  // 🔴 参数名**不能**叫 key：addEventListener 的回调签名叫 (event)，
  //   传进来的就是那个 CustomEvent 对象本身。直接当 key 用会拿到
  //   '[object CustomEvent]' —— 于是'打开项目详情'永远匹配不上、点了不跳，
  //   而页面毫无报错（本轮真机验收靠菜单 warn 文案里的 [object CustomEvent] 抓到的）。
  const key = evt && evt.detail ? evt.detail.key : evt
  const row = ui.rowMenuTarget
  closeRowMenu()
  if (key === 'open') {
    // V1.32：文件夹行的「打开」是**进入层级**（drillUrl），项目行才是项目详情 ——
    // 两条路都只认 payload 下发的 URL，前端不拼宿主路由。
    const url = row && row.folder ? row.drillUrl : drillTo(row, 'project')
    if (url) window.location.assign(url)
    else ui.listError = row && row.folder
      ? 'payload 未下发文件夹落点（drillUrl），无法进入该文件夹'
      : 'payload 未下发项目详情落点（detailUrl），无法打开'
    return
  }
  runRowAction(key, row)
}

/**
 * 行菜单 7 项的分发。真源端点点在 payload 下发的 row.actions[key] 上，
 * 前端只按 ROW_ACTION_KINDS 决定「以哪种方式落地」：
 *   modal → RowActionModal（edit/access/move/comment 四种浮体）
 *   post  → 直接 POST 原生批量端点（archive_group / export_projects），原生自己判权限
 *   link  → 原生 activities_action（type: :link）直接跳
 * ⚠ 拿不到端点（payload 没下发 / enabled 为 false）就**显式报错文案**，
 *   绝不回落原型演示值，也绝不静默失败。
 */
async function runRowAction(key, row) {
  ui.listError = ''
  const act = row && row.actions ? row.actions[key] : null
  if (!act || !act.enabled || !act.url) {
    ui.listError = `原生端点未就绪：行菜单「${key}」payload 未下发可用端点`
    console.warn(`[eln_ui] 行菜单「${key}」无真源端点（显式留白，非演示文案）`, act || {})
    return
  }

  const meta = ROW_ACTION_KINDS[key] || { kind: 'link' }

  if (meta.kind === 'modal') {
    openRowAction(key, row)
    return
  }

  if (meta.kind === 'link') {
    window.location.assign(act.url)
    return
  }

  // post：archive / export —— 原生这俩都是**批量**端点，body 键名由 payload 下发
  // （`body_key`，例如 archive → `project_ids`、文件夹删除 → `project_folder_ids`）。
  // ⚠ 不能写死 `project_ids`：发错键名服务端会「静默匹配 0 行」后回一个 422，
  //   用户只看到"失败"，永远不知道为什么。
  try {
    const bodyKey = act.body_key || 'project_ids'
    const body = {}
    body[bodyKey] = [row.id]
    await sendForm(act.url, 'POST', body)
    showToast(key === 'archive' ? '已提交归档（原生 /projects/archive_group）' : '已提交导出（原生 /teams/:id/export_projects）')
    if (key === 'archive') {
      // 归档后本行会从活动列表消失（原生 archive_group 也是这个语义），
      // 停 1s 再刷新，避免"点了没反应"和"列表突然空了"两种观感。
      setTimeout(() => refreshList(), 1000)
      return
    }
    await refreshList()
  } catch (e) {
    ui.listError = e && e.message ? e.message : '原生端点调用失败'
  }
}

window.addEventListener('eln:row-menu', onRowMenuAction)

onMounted(() => {
  document.addEventListener('click', onDocClick)
  document.addEventListener('keydown', onDocKeydown)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
  document.removeEventListener('keydown', onDocKeydown)
  window.removeEventListener('eln:row-menu', onRowMenuAction)
})

const viewRenderLabel = computed(
  () => (viewRenders.find((r) => r.value === ui.viewRender) || viewRenders[0]).label
)
const viewModeLabel = computed(
  () => (viewModes.find((m) => m.value === ui.viewMode) || viewModes[0]).label
)

// 原生 list.vue 的 toolbarActions：归档态**不给**建项目（建了也看不见）。
const showCreateProject = computed(
  () => ui.canCreateProject && ui.viewMode !== 'archived'
)

// ------------------------------------------------------------
// V1.31 分页
//
// 数据源一律是**服务端**下发的 ui.pagination（唯一真源）：
//   perPageOptions —— 档位集合（当前 [0, 20, 50, 100]），前端不写死第二份
//   totalEntries   —— **筛选后**的总条数
//   totalPages     —— 总页数
//
// ⚠ 为什么「共 N 条」不能用 projects.length：分页生效后那只是**当前页**行数，
//   会写出「共 20 条」这种一眼假的数字，页码控件也无从生成。
//   服务端分页 + 前端全量切片假装分页，是 spec SCN-PROJ-LIST-13 明令禁止的。
// ------------------------------------------------------------

/** 档位集合：服务端下发优先；原型独立跑（没有 payload）时用同值初值兜底 */
const perPageOptions = computed(() => {
  const raw =
    ui.pagination && Array.isArray(ui.pagination.perPageOptions)
      ? ui.pagination.perPageOptions
      : [0, 20, 50, 100]
  const out = raw
    .map((n) => Math.trunc(Number(n)))
    .filter((n) => Number.isFinite(n) && n >= 0)
  return out.length ? out : [0, 20, 50, 100]
})

// 档位文案：0 = 全部。
// ⚠ 不能渲染成「0」或「0 条」——「每页 0 条」在业务上无意义，0 表达的是
//   「不分页、一次看完」，用户看到「0」只会以为是坏了。
function perPageLabel(n) {
  return Number(n) === 0 ? '全部' : String(n)
}

/** 筛选后总条数；服务端没给（原型独立跑）时退化为当前行数 */
const totalEntries = computed(() => {
  const t = ui.pagination ? Number(ui.pagination.totalEntries) : NaN
  return Number.isFinite(t) && t > 0 ? t : projects.length
})

const totalPages = computed(() => {
  const fromServer = ui.pagination ? Number(ui.pagination.totalPages) : NaN
  if (Number.isFinite(fromServer) && fromServer >= 1) return fromServer

  const per = Number(ui.perPage)
  if (!Number.isFinite(per) || per <= 0) return 1 // 档位 0（全部）只有一页
  return Math.max(Math.ceil(totalEntries.value / per), 1)
})

/** 总条数未超过一页 ⇒ 不渲染页码控件（spec SCN-PROJ-LIST-13 第 5 条） */
const showPager = computed(() => totalPages.value > 1)

/** 信息条计数：有勾选时显示「已选 x / 共 N 项」 */
const countText = computed(() => {
  const total = totalEntries.value
  const picked = ui.selectedProjectIds.length
  return picked > 0 ? `已选 ${picked} / 共 ${total} 项` : `共 ${total} 条`
})

/**
 * 页码窗口：总页数 ≤ 7 全列；超过则「首页 … 当前±1 … 末页」。
 * 不把 8+ 个页码全铺开 —— 原生分页控件也没这么做，且会把信息条挤变形。
 * 返回项可能是数字或占位串 '…'（模板里对 '…' 置灰且不可点）。
 */
const pageNumbers = computed(() => {
  const total = totalPages.value
  const cur = Math.min(Math.max(Number(ui.page) || 1, 1), total)
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1)

  const out = [1]
  const start = Math.max(2, cur - 1)
  const end = Math.min(total - 1, cur + 1)
  if (start > 2) out.push('…')
  for (let p = start; p <= end; p += 1) out.push(p)
  if (end < total - 1) out.push('…')
  out.push(total)
  return out
})

function onPerPageChange(e) {
  setPerPage(e.target.value)
}

// 页头副标题（V1.32 改用 ui.projectCount 而不是分页总数）：
//   projectCount = **纯项目行**数；分页总数（totalEntries）含文件夹行。
//   用错就会把文件夹算成项目 —— 而且会同时打破 spec SCN-DASH-8 的
//   「工作台卡片数字 ≡ 落点页项目行条数」不变式（工作台那张卡只说「参与项目」）。
// ⚠ 判别口径与 store 里其它处一致：`ui.listUrl` 为空 = 原型独立跑（没有 payload），
//   此时 projectCount 恒 0（会把原型渲染成「共 0 个项目」而列表里明明有行），
//   所以退化成本地数一遍项目行。真机上永远走服务端那个数。
const subtitle = computed(() => {
  const n = ui.listUrl ? ui.projectCount : projects.filter((r) => !r.folder).length
  const base = `共 ${n} 个项目 · ${viewModeLabel.value}`
  const tail =
    ui.viewMode === 'archived'
      ? '归档项目只读，不提供新建'
      : '可见范围按角色过滤（项目负责人仅见本人负责的项目）'
  return `${base} · ${tail}`
})

function pickRender(v) {
  setViewRender(v)
  closeMenu()
  // 表格 ⇄ 卡片切换会销毁/重建 .table-scroll（v-if），CSS 变量随元素一起没了。
  // 切回表格时补写一次，否则用户拖好的列宽在「切卡片再回来」后被悄悄重置。
  if (v === 'table') nextTick(() => applyVars())
}

function pickMode(v) {
  setViewMode(v)
  closeMenu()
}

function onSearchInput(e) {
  setQuery(e.target.value)
}

// 「全选」只覆盖**项目行**（见模板里勾选格那段收窄说明）——
// 用 projects.length 会把文件夹行也算进分母，导致「明明全选了却显示未全选」。
const allSelected = computed(
  () => selectableRows.value.length > 0 &&
    ui.selectedProjectIds.length === selectableRows.value.length
)

function toggleAll() {
  if (allSelected.value) clearSelection()
  else {
    ui.selectedProjectIds = selectableRows.value.map((p) => p.id)
    ui.bulkBarVisible = true
  }
}

// 原生 CounterRenderer：轨道 96×4，completed/total 为 0 时最小 3%
function expWidth(p) {
  if (p.completed === 0 || p.total === 0) return 96 * 0.03
  return Math.round(96 * (p.completed / p.total))
}

function taskWidth(p) {
  const done = Number(p.tasksCompleted || 0)
  const total = Number(p.tasksTotal || 0)
  if (done === 0 || total === 0) return 96 * 0.03
  return Math.round(96 * (done / total))
}

// 卡片视图里轨道是撑满的，用百分比而非固定 96px
function expPct(p) {
  if (p.completed === 0 || p.total === 0) return 3
  return Math.round((p.completed / p.total) * 100)
}

function avatarStyle(color) {
  const c = avatarPalette[color] || avatarPalette.blue
  return { background: c.bg, color: c.fg }
}

function openMenu(e, project) {
  // 第 4 个参数 = 这一行真正能点的菜单项（payload 的 actions 已按原生权限算过）
  openRowMenu(project, e.clientX - 170, e.clientY + 8, menuItemsFor(project))
}

// ---------- 下钻的两条非鼠标路径（键盘 / 行菜单）----------
// 铁律：URL 一律走 drillTo（payload 下发的 detailUrl），前端不拼宿主路由。

/** 行菜单 → 「打开项目详情」：菜单关掉再跳，否则菜单留在页面上跟着跳 */
function drillToRow(row) {
  closeRowMenu()
  const url = row && row.folder ? row.drillUrl : drillTo(row, 'project')
  if (url) window.location.assign(url)
  else if (row && row.folder) ui.listError = 'payload 未下发文件夹落点（drillUrl），无法进入该文件夹'
}

/**
 * 行菜单动作分发（RowMenu 组件只负责「哪个动作被点了」，落点由这里决定）。
 *   open → 下钻到 payload 下发的真实 detailUrl（与点击行名同一出口 drillTo）
 *   其余原生存量项：真源都还没接，取不到就**显式留白**，不编演示文案。
 */
// 🔴 行菜单挂在 Root 层（见 entries/project_list.js），它的 @action 以 window 事件
//    'eln:row-menu' 广播回来。列表页在这里接 —— Root 与列表页互相不认识，
//    靠一个具名事件解耦，避免把菜单组件塞进列表页（会被 overflow 裁掉）。
//    绑在 onMounted 前（本函数被 onMounted 的监听注册用到，必须早于注册）。

/**
 * 键盘下钻 + 焦点导航。
 *   ↑/↓   在行之间移动焦点（不动页面滚动条，只动 focusIndex）
 *   Enter 下钻到当前焦点行的项目详情（**列表页唯一的键盘下钻出口**）
 *   Esc   关行菜单 / 清焦点（原生 projects 页 Esc 只收菜单，不跳页）
 *
 * 🔴 作用域：只处理 .trow 自身 keydown（@keydown 绑在行上），
 *    所以不会截获工具栏输入框的打字 —— 搜索框里敲 Enter 不该跳详情。
 */
function onRowKeydown(e, i) {
  if (e.key === 'Enter') {
    e.preventDefault()
    focusIndex.value = i
    drillToRow(projects[i])
    return
  }  if (e.key === 'Escape') {
    closeRowMenu()
    focusIndex.value = -1
    return
  }
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault()
    const next = e.key === 'ArrowDown' ? i + 1 : i - 1
    if (next < 0 || next >= projects.length) return
    focusIndex.value = next
    // 焦点要真的落到 DOM 上，否则 Enter 打在当前焦点（可能是搜索框）里
    // ⚠ 选择器必须用 rowDomId —— 文件夹行是 `folder-<id>`，写成 `row-<id>`
    //   在两类 id 相同的行上会**命中另一类行**（静默错焦点，比找不到更坏）。
    const el = document.querySelector(`#eln-project-list [data-e2e="${rowDomId(projects[next])}"]`)
    if (el) el.focus()
  }
}
</script>

<style scoped>
.proj-list {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 18px;
}

/* ---------- 工具栏 ---------- */
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.tb-left {
  display: flex;
  gap: 8px;
}
.tb-center {
  display: flex;
  gap: 8px;
}
.tb-right {
  display: flex;
  gap: 8px;
}
.tb-dropdown {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  height: 32px;
  padding: 0 12px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-text-menu);
}
.tb-dropdown svg:last-child {
  color: var(--color-placeholder);
}
.tb-dropdown:hover {
  background: #F9FAFB;
}

/* ---------- 下拉菜单（原生 MenuDropdown） ---------- */
.tb-dropdown-wrap {
  position: relative;
}
.tb-menu {
  position: absolute;
  top: calc(100% + 6px);
  right: 0;
  z-index: 30;
  min-width: 148px;
  padding: 6px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 10px;
  box-shadow: var(--shadow-pop, 0 8px 24px rgba(24, 24, 27, 0.12));
  display: flex;
  flex-direction: column;
}
.tb-menu-item {
  display: flex;
  align-items: center;
  height: 32px;
  padding: 0 10px;
  border: none;
  background: transparent;
  border-radius: 6px;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  text-align: left;
  cursor: pointer;
  white-space: nowrap;
}
.tb-menu-item:hover {
  background: var(--color-fill-soft, #F5F5F7);
}
.tb-menu-item.on {
  color: var(--color-primary);
  font-weight: 500;
}
.cols-menu {
  min-width: 168px;
}
.cols-item {
  gap: 8px;
}
.cols-item.disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
/* 钉住组 / 未钉组的分隔线（原生 pinnedSeparator 同款：线以上 = 钉住区） */
.cols-sep {
  height: 1px;
  margin: 4px 0;
  background: var(--color-border);
}
/* V1.34 钉列图钉：右缘对齐（原生 Manage columns 弹窗同款布局），on = 已钉住 */
.cols-item {
  display: flex;
  align-items: center;
}
.cols-item-label {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.col-pin-btn {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 4px;
  color: var(--color-text-menu, #64748b);
  cursor: pointer;
  opacity: 0.55;
  transform: rotate(45deg); /* 斜置 = 未钉（原生 pin 图标语义同款） */
}
.col-pin-btn:hover {
  opacity: 1;
  background: rgba(15, 23, 42, 0.06);
}
.col-pin-btn.on {
  opacity: 1;
  color: var(--el-color-primary, #2563eb);
  background: rgba(37, 99, 235, 0.1);
  transform: none; /* 回正 = 已钉住 */
}
/* 「重置列宽」：与上方 checkbox 行之间加一条分隔，避免看起来像又一个列项 */
.cols-reset {
  margin-top: 4px;
  padding-top: 8px;
  border-top: 1px solid var(--color-divider);
  width: 100%;
  justify-content: flex-start;
  color: var(--color-text-secondary);
  font-size: 12px;
}
.cols-reset:hover {
  color: var(--color-primary);
}

/* ---------- 搜索框（点图标展开，原生 Search 同款） ---------- */
.search-wrap {
  display: flex;
  align-items: center;
}
.search-input {
  width: 180px;
  height: 32px;
  margin-left: 8px;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: var(--color-card);
  outline: none;
}
.search-input:focus {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}

/* ---------- 刷新提示 ---------- */
.tb-hint {
  font-size: 12px;
  color: var(--color-text-secondary);
  min-height: 16px;
}
.tb-hint.err {
  color: var(--color-danger, #DC2626);
}

/* ---------- 空态 ---------- */
.empty-row {
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  color: var(--color-placeholder);
}

/* ---------- V1.31 分页信息条 ----------
   位置：表格卡片内、滚动区**之下**（在 .table-scroll 外面）——列横向滚动时它不跟着跑。
   ⚠ 顶边线不能省：没有它最后一行数据会紧贴分页条，看起来像「最后一行特别高」。
   ⚠ 右侧 padding 必须让开宿主全局「语言切换」悬浮球（fixed 贴右下角、z-index 更高）：
     不让开的话，用户滚到页底时它正好压住「下一页」按钮 —— 翻页是本条最高频的动作，
     被一个装饰性悬浮球挡住不可接受（真机截图 pager_shot_page1.png 实测遮挡）。 */
.table-pager {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 112px 12px 20px;
  border-top: 1px solid var(--color-divider);
  font-size: 13px;
  color: var(--color-text-secondary);
}
.tp-left {
  display: flex;
  align-items: center;
  gap: 8px;
}
.tp-select {
  height: 28px;
  padding: 0 6px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  background: var(--color-card);
  color: var(--color-text);
  font-size: 13px;
  font-family: inherit;
}
.tp-count {
  margin-left: 4px;
}
.tp-right {
  display: flex;
  align-items: center;
  gap: 4px;
}
.tp-btn {
  min-width: 28px;
  height: 28px;
  padding: 0 8px;
  border: 1px solid var(--color-border);
  background: var(--color-card);
  border-radius: 6px;
  font-size: 12px;
  font-family: inherit;
  color: var(--color-text);
}
.tp-btn:hover:not(:disabled) {
  border-color: var(--color-primary);
  color: var(--color-primary);
}
.tp-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.tp-btn.page.on {
  background: var(--color-primary);
  border-color: var(--color-primary);
  color: #ffffff;
}
/* 页码省略号：占位不可点。保留 .tp-btn 的尺寸，否则信息条会随页码段数跳动 */
.tp-btn.gap {
  border-color: transparent;
  background: transparent;
  cursor: default;
}

/* ---------- V1.32 文件夹层级面包屑 ----------
   放在工具栏与表格卡片之间（与「刷新提示」同一竖列节奏）。
   ⚠ 分隔符用 '/'：本工程既有面包屑（ExperimentDesign.vue / EquipmentBooking.vue）
     一律是 '/'。spec OPEN-2（面包屑分隔符 '>' vs ' / '）**尚未裁决** ——
     裁决结果若是 '>'，本文件只有下面 .fc-sep 一处要改。 */
.folder-crumbs {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: var(--color-text-secondary);
  /* 层级再深也不要撑破内容区：横向滚动而不是换行（换行会把表格往下顶） */
  overflow-x: auto;
  white-space: nowrap;
}
.fc-sep {
  color: var(--color-placeholder);
}
.fc-link {
  color: var(--color-text-secondary);
  text-decoration: none;
}
.fc-link:hover {
  color: var(--color-primary);
}
/* 当前层：加粗 + 主色，明确"你在这里" */
.fc-link.current {
  color: var(--color-text);
  font-weight: 500;
}
.fc-spacer {
  flex: 1;
}
.fc-up {
  display: inline-flex;
  align-items: center;
  height: 28px;
  padding: 0 10px;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  background: var(--color-card);
  color: var(--color-text-menu);
  text-decoration: none;
  font-size: 13px;
}
.fc-up:hover {
  background: #F9FAFB;
}

/* ---------- V1.32 文件夹行 ---------- */
/* 文件夹名：图标 + 文本一行内对齐（原生 NameRenderer 同款） */
.folder-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.folder-link svg {
  color: var(--color-primary);
  flex-shrink: 0;
}
/* 「x 个项目 | y 个文件夹」：第二行小字，不抢名称的视觉权重 */
.folder-info {
  display: block;
  margin-top: 2px;
  padding-left: 21px; /* 与名称文本左对齐（图标 15 + gap 6） */
  font-size: 12px;
  color: var(--color-placeholder);
}
/* 文件夹行整行可点（进层级），给一点可点暗示，但不做成按钮 */
.trow.is-folder .col-name {
  cursor: pointer;
}
/* 卡片视图里的文件夹卡：与项目卡同尺寸，但内容只有名称 + 计数 */
.folder-card .pc-meta {
  gap: 10px;
}

/* ---------- 卡片视图 ---------- */
.cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 16px;
}
.proj-card {
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.proj-card:hover {
  border-color: var(--color-primary);
}
.pc-top {
  display: flex;
  align-items: center;
  gap: 8px;
}
.pc-top .proj-link {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.pc-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}
.pc-row {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--color-text);
}
.pc-label {
  width: 52px;
  flex-shrink: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.pc-exp {
  margin-top: 2px;
}

/* ---------- 表格 ---------- */
.table-card {
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
  /* ⚠ 原来是 overflow:hidden（为裁表格圆角）—— 但它会把 .table-scroll 的
     **横向滚动条一起裁掉**（滚动条在 border-box 内侧）。改成只裁上下：
     左右放行才能保住圆角又不挡滚动条。 */
  overflow-y: hidden;
  overflow-x: clip;
}
.table-scroll {
  padding: 0;
  /* 横向滚动落点：列总宽（--cw-* 之和 + gap + padding）超出容器时出滚动条 */
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: thin;
}
/* 拖拽时禁掉文字选中，否则整片变蓝（类由 composable 在 pointerdown 时挂上 body） */
body.eln-col-resizing,
body.eln-col-resizing * {
  user-select: none !important;
}
body.eln-col-resizing {
  cursor: col-resize;
}

/* 画布 4:329 表格卡片 padding=0、高 232 = 表头 40 + 4×48（零内缩）；
   内缩 20 + 列距 12 由行自带 —— 画布 4:330 / 4:341「padding:0 20 / gap:12」 */
.thead,
.trow {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 20px;
  /* 🔴 关键：flex 行默认 width:auto = 撑满父级，列宽超出时是「溢出」而不是
     「把父级撑宽」，.table-scroll 的 overflow-x:auto 也就永远不会触发。
     width:max-content 让行宽 = 列宽之和 + gap + padding，超出即产生横向滚动。
     （表头与数据行必须同宽，否则滚动时表头和数据列会错位） */
  width: max-content;
  min-width: 100%;
}
.thead {
  height: 40px;
  background: var(--color-table-header);
  border-radius: var(--radius-table-header);
}
.thead .th {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-secondary);
  white-space: nowrap;
  /* ⚠ 原来整列 overflow:hidden —— 但它会把列宽手柄（right:-3px，出血到列外）
     一起裁掉，手柄只剩 3px 可见、几乎点不中。改成：
     列头本身不裁（visible），改由**文字 span 自己**做 ellipsis。 */
  overflow: visible;
  /* 🔴 手柄是 position:absolute + inset:0，命中区高度 = 元素内容盒高度。
     父级 .thead 是 align-items:center（把它压成内容高 18px），
     结果手柄只有 18px 高 —— 上下各 11px 是死区，拖起来很难受。
     显式 align-self:stretch 让手柄吃满表头 40px 高度（与原生 ag-grid 手柄一致）。 */
  align-self: stretch;
}
/* 列头文字做省略号（原来靠父级 text-overflow，现在父级不裁了） */
.thead .th > span:not(.col-resize-handle) {
  overflow: hidden;
  text-overflow: ellipsis;
}
/* 列头排序（原生同款）：可点、hover 微亮，激活列变主色、箭头紧跟文字 */
.th.sortable {
  cursor: pointer;
  user-select: none;
  gap: 4px;
  display: flex;
  align-items: center;
}
.th.sortable:hover {
  color: var(--color-text-primary);
}
.th.sortable .sort-arrow {
  font-size: 10px;
  opacity: 0;
  transition: opacity 0.15s;
  flex-shrink: 0;
}
.th.sortable:hover .sort-arrow,
.th.sortable.active .sort-arrow {
  opacity: 1;
}
.th.sortable.active {
  color: var(--el-color-primary, #2563eb);
  font-weight: 600;
}
.trow {
  height: 48px;
  border-bottom: 1px solid var(--color-divider);
  /* V1.33 钉列前置：给行一个不透明底色（= 卡片底色，视觉无变化）。
     钉列单元格 background-color:inherit 跟着行走 —— hover / focused 时
     钉住的单元格自动同步行色，滚动时不会「下面的列从钉列底下穿出来」。 */
  background-color: var(--color-card);
}
.trow:last-child {
  border-bottom: none;
}
.trow:hover {
  background: #FAFAFA;
}
/* ------------------------------------------------------------
   V1.34 钉列（多列独立钉住）—— 原生 ag-grid pinned 区的同款可观察行为
   · .pin 由 pinCell() 在**所有钉住的可见列**上动态挂载（v-bind），
     顺序不靠 DOM：靠 order:0（钉住组）vs order:1（未钉组）分组
   · th / td 分层 z-index：钉列表头 > 钉列单元格 > 普通滚动内容，
     且不能压过列宽手柄（z-index:3，在 th 内部，同上下文不受影响）
   · background 继承行/表头底色（上行 .trow 已给不透明底）
   · .pin-last = 钉住区右边界投影（原生钉区同款视觉信号）
   ------------------------------------------------------------ */
.th.pin {
  background-color: inherit;
  z-index: 4;
}
.td.pin {
  background-color: inherit;
  z-index: 2;
}
.pin-last {
  box-shadow: 4px 0 8px -2px rgba(15, 23, 42, 0.14);
}
.td {
  font-size: 13px;
  color: var(--color-text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* 列宽（对齐画布：选择40/星标28/名称220/ID76/状态92/截止96/负责人112/已完成实验100/访问权限116/操作40）
   🔴 全部改成 var(--cw-*)：变量由 composables/useColumnResize.js 在 .table-scroll 上写入，
   表头与数据行共用这一条规则 → 拖拽时只更新一个变量，浏览器自己重排，200 行也不卡。
   ⚠ 关键改动：col-name 从 `flex:1 1 200px` 改成**定宽** —— 只要它还 flex:1，
   它就会吃掉所有剩余空间，列总宽永远等于容器宽，**横向滚动条永远不出现**。
   要出滚动条就必须让所有列都是定宽，总宽由列宽之和决定。 */
.col-check { width: var(--cw-check, 40px); flex-shrink: 0; display: flex; align-items: center; justify-content: center; }
.col-star { width: var(--cw-star, 28px); flex-shrink: 0; display: flex; align-items: center; justify-content: center; }
.col-name { width: var(--cw-name, 220px); flex-shrink: 0; }
.col-id { width: var(--cw-id, 76px); flex-shrink: 0; }
.col-status { width: var(--cw-status, 92px); flex-shrink: 0; display: flex; align-items: center; }
/* ↓ 并集补齐的原生列（宽度对齐原生 minWidth 语义：够放内容，不靠挤压腾地方） */
.col-start { width: var(--cw-start, 96px); flex-shrink: 0; }
.col-due { width: var(--cw-due, 96px); flex-shrink: 0; }
.col-owner { width: var(--cw-owner, 112px); flex-shrink: 0; display: flex; align-items: center; gap: 6px; }
.col-exp { width: var(--cw-exp, 100px); flex-shrink: 0; }
.col-tasks { width: var(--cw-tasks, 100px); flex-shrink: 0; }
.col-users { width: var(--cw-users, 116px); flex-shrink: 0; }
.col-comments { width: var(--cw-comments, 64px); flex-shrink: 0; }
.col-desc { width: var(--cw-desc, 240px); flex-shrink: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.col-created { width: var(--cw-created, 128px); flex-shrink: 0; }
.col-updated { width: var(--cw-updated, 128px); flex-shrink: 0; }
.col-archived { width: var(--cw-archived, 96px); flex-shrink: 0; }
.col-action { width: var(--cw-action, 40px); flex-shrink: 0; display: flex; align-items: center; justify-content: center; }

/* 列宽拖拽手柄（原生 ag-grid resizable 手柄位：贴在列头右缘）
   🔴 不用伪元素 ::after —— 伪元素收不到 pointerdown 事件，没法拖。
   必须是真实 DOM 节点 + @pointerdown。 */
.col-resize-handle {
  position: absolute;
  top: 0;
  right: -4px;              /* 出血到 gap 里（gap 12px），命中区 8px 好点 */
  bottom: 0;                /* 上下贴齐表头，配合父级 align-self:stretch 吃满 40px */
  width: 8px;
  flex-shrink: 0;
  cursor: col-resize;
  z-index: 3;
  touch-action: none;        /* 关键：否则触屏/拖拽会被当成滚动，鼠标一按就滚 */
  user-select: none;
}
.col-resize-handle::before {
  content: '';
  position: absolute;
  top: 6px;
  bottom: 6px;
  left: 3px;                 /* 8px 命中区居中 2px 竖线 */
  width: 2px;
  background: transparent;
  border-radius: 1px;
  transition: background 0.15s;
}
.th { position: relative; }   /* 手柄的定位上下文 */
.th:hover .col-resize-handle::before,
.col-resize-handle.active::before {
  background: var(--color-primary, #2563eb);
}

/* 焦点行：外描边 + 浅底，与 hover 区分开（hover 是 #FAFAFA，焦点要更明显，
   否则用户按 ↑↓ 时看不出焦点在哪一行，Enter 等于盲跳）
   ⚠ 行菜单样式不在本文件 —— RowMenu 组件自持 scoped 样式，避免两处各写一份。 */
.trow.focused {
  background: #F0F6FF;
  box-shadow: inset 0 0 0 2px var(--el-color-primary, #2563eb);
}
.trow:focus-visible {
  outline: none;
}

/* 勾选框 / 星标：通用类已提取至 styles/tokens.css（.checkbox / .star） */

.proj-link {
  color: var(--color-text);
  font-weight: 500;
  text-decoration: none;
}
.proj-link:hover {
  color: var(--color-primary);
}
.num {
  font-family: var(--font-en);
  font-size: 12px;
  color: var(--color-text-secondary);
}

/* 已完成实验：CounterRenderer 96×4 轨道 */
.exp-cell {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.exp-text {
  font-family: var(--font-en);
  font-size: 11px;
  color: var(--color-text-secondary);
  line-height: 1;
}
.exp-track {
  width: 96px;
  height: 4px;
  border-radius: 2px;
  background: var(--color-border);
  overflow: hidden;
}
.exp-fill {
  height: 100%;
  border-radius: 2px;
  background: var(--color-primary);
}

/* 头像 */
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
.avatar.sm {
  width: 24px;
  height: 24px;
}
.avatar.more {
  background: var(--color-border);
  color: var(--color-subtle-text);
  font-size: 10px;
}
.avatar-group {
  display: flex;
  align-items: center;
}
.avatar-group .avatar + .avatar {
  margin-left: -6px;
}
.avatar-group .avatar {
  border: 2px solid var(--color-card);
}

/* 行操作 ⋯ */
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
</style>
