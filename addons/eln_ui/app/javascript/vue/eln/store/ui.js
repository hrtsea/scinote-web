import { reactive } from 'vue/dist/vue.esm-bundler.js'

// ============================================================
// 全局 UI 状态：浮层显隐 + 选中态 + 列表工具栏
// 由 store 统一控制，避免各页面各自维护弹层状态造成不一致。
//
// 原型独立跑（npm run dev）与挂进 SciNote（真机）共用同一份 store：
//   - 没注入宿主能力时（listUrl 为空 / createUrls 为空 / 选项数组为空），
//     工具栏按钮照样能点，但只改本地状态、不发起请求 —— 原型仍是纯演示；
//   - 注入后（src/entries/project_list.js 写入）才会真打原生端点。
// 这样两边一套代码，不需要在组件里写 if (真机) 分支。
// ============================================================
// ---------------------------------------------------------------------------
// 列集合（唯一真源）
//
// 列集合 = 原型列 ∪ 原生 /projects 表格列（app/javascript/vue/projects/list.vue
// 的 columnDefs：name / favorite / code / status / due_date / start_date /
// supervised_by / completed_experiments / completed_tasks / created_at /
// updated_at / users / comments / description / archived_on）。
//
// ⚠ 这份清单以前住在 ProjectList.vue 里，而钉列归一化（前缀集合 / 存档清洗）
//   需要列序 → 只能在 store 里再抄一份 = 第二真源，迟早改漏。
//   现在上提到 store：组件 import 它渲染列管理菜单与钉列偏移，store 用它做
//   钉列归一化，两边永远同一份。
//
//   key          —— 列标识（columnVisibility / pinned 里存的就是它）
//   label        —— 列管理菜单里的列名
//   locked       —— 不允许隐藏（name 列：关掉整行没内容可点，原生也不给关）
//   alwaysPinned —— 恒钉且不可取消（check 列 = 原生 selectionColumnDef，
//                   table.vue 里 pinned:'left'，saveTableState 还会强制写回）
//
// 注：archived（归档日期）只在归档视图渲染 —— 那是渲染层的事（原生 list.vue
//     也是按 view_mode push 该列），不影响这里的列集合。
// ---------------------------------------------------------------------------
export const COLUMN_DEFS = [
  { key: 'check', label: '选择', alwaysPinned: true },
  { key: 'star', label: '星标' },
  { key: 'name', label: '项目名称', locked: true },
  { key: 'id', label: 'ID' },
  { key: 'status', label: '状态' },
  { key: 'start', label: '开始日期' },
  { key: 'due', label: '截止日期' },
  { key: 'owner', label: '项目负责人' },
  { key: 'exp', label: '已完成实验' },
  { key: 'tasks', label: '已完成任务' },
  { key: 'users', label: '访问权限' },
  { key: 'comments', label: '评论' },
  { key: 'desc', label: '描述' },
  { key: 'created', label: '创建时间' },
  { key: 'updated', label: '更新时间' },
  { key: 'archived', label: '归档日期' },
  { key: 'action', label: '操作' }
]

/** 列的 DOM/渲染序（钉列分组与偏移计算都按它；columnDefs 的顺序即真源） */
export const COLUMN_KEYS = COLUMN_DEFS.map((c) => c.key)

/** 恒钉列（原生 checkbox 列同款）；钉列归一化后必然在集合里 */
const ALWAYS_PINNED = COLUMN_DEFS.filter((c) => c.alwaysPinned).map((c) => c.key)

export const ui = reactive({
  // 项目列表页浮层
  navigatorOpen: false,
  newProjectOpen: false,
  newFolderOpen: false,
  // 「新建项目」按钮权限（PRD §7.4 SCN-PROJ-LIST-4：仅单位管理员可见可用）。
  // 默认 true = 原型行为（原型 mock 数据不体现权限）；
  // 挂进 SciNote 时由入口 src/entries/project_list.js 按宿主判断覆写。
  canCreateProject: true,
  // 「新建文件夹」按钮权限（原生 TeamPermissions::CREATE_PROJECT_FOLDERS）。
  // 没有权限时按钮**不渲染**（与原生 list.vue 的 createFolderUrl 为空同口径），
  // 而不是渲染出来点了报错。
  canCreateFolder: true,
  filterOpen: false,
  rowMenuOpen: false,
  rowMenuPos: { x: 0, y: 0 },
  rowMenuTarget: null, // 当前右键/点击的行数据
  // 行菜单项**按行动态**（原生 Toolbars::ProjectsService 是 compact 掉没权限的项，
  // 不是渲染出来再置灰）；打开菜单时由列表页按 payload 的 actions 算好塞进来。
  rowMenuItems: [],
  // 行动作浮层（编辑 / 移动 / 访问权限 / 评论四体的容器）
  rowAction: null, // { kind, row } 或 null
  bulkBarVisible: false,

  // 选中行集合（项目列表勾选）
  selectedProjectIds: [],

  // 当前路由面包屑辅助
  currentProject: null,

  // ----------------------------------------------------------
  // 项目列表工具栏（原生 toolbar.vue 那 7 个控件）
  //
  // viewRender      —— 表格 / 卡片（前端切换，不动服务端）
  // viewMode        —— 活动 / 归档，切了要重拉列表（原生 view_mode 参数）
  // query           —— 顶部搜索框（debounce 后重拉，对应原生 search 参数）
  // filters         —— 筛选面板条件；键名与原生 Lists::ProjectsService 对齐，
  //                    这样筛出来的集合 == 原生项目页筛出来的集合
  // columnVisibility—— 列显隐，纯前端（列本身不动）
  // foldersOpen     —— 新建项目时的「归入文件夹」下拉
  //
  // 以下四项只有挂进 SciNote 才有值：
  //   listUrl      —— json 出口（条件改完只重拉数据，不整页重载）
  //   createUrls   —— 新建项目 / 新建文件夹的原生 POST 端点
  //   folders/members/headOfProjects/statuses/defaultRoles —— 下拉可选项
  //   listConsumer —— 由 entry 注入：把拉回来的数据写回组件读的那份数组
  // ----------------------------------------------------------
  viewRender: 'table',
  viewMode: 'active',
  query: '',
  searchOpen: false,
  // 列头排序（原生 order[column] + order[dir]）：'' 表示未排序（走服务端默认 name asc）
  sort: { column: '', dir: '' },
  // ----------------------------------------------------------
  // V1.31 分页
  //
  //   page      —— 当前页码（1-based，与原生 kaminari 同口径；服务端会把它归一化，
  //                传 0 / 负数 / 乱码都当第 1 页）
  //   perPage   —— 每页条数，**档位真源在服务端** payload.pagination.perPageOptions
  //                （当前 [0, 20, 50, 100]）。`0` 是合法值 = 全部（不分页）。
  //                这里给默认值是给「原型独立跑」（没有 payload）一个可渲染的初值，
  //                不构成第二套档位定义 —— 下拉的 option 一律由 perPageOptions 渲染。
  //   pagination—— 服务端回的分页状态，渲染信息条与页码控件全读它。
  //                ⚠ 绝不能用 projects.length 当「共 N 条」：分页后那只是当前页行数，
  //                  会写出「共 20 条」这种明显错的数字。
  // ----------------------------------------------------------
  page: 1,
  perPage: 20,
  pagination: {
    page: 1,
    perPage: 20,
    perPageOptions: [0, 20, 50, 100],
    totalEntries: 0,
    totalPages: 1
  },
  // ----------------------------------------------------------
  // V1.32 行集合（项目行 ∪ 文件夹行）
  //
  //   projectCount —— 当前结果集里的**纯项目行**数（筛选后、分页前）。
  //                   页头「共 N 个项目」读它 —— **不是** pagination.totalEntries：
  //                   后者含文件夹行，用错会把文件夹算成项目，
  //                   并且会破坏 spec SCN-DASH-8 的「卡片数字 ≡ 列表项目行数」不变式。
  //   currentFolder—— 当前所在文件夹 {id,name,code,url}；顶层时为 null。
  //                   ⚠ 只读 payload，**不参与请求参数拼装**（参数走 folderId 那一格）。
  //   folderId     —— 当前层级的文件夹数字主键（字符串）；'' = 顶层。
  //                   它是 refreshList 必须带上的参数，否则每次排序/翻页/筛选都会
  //                   悄悄跳回顶层（只在服务端生效，页面无任何异常提示，是最难查的一类）。
  //   folderNav    —— 服务端下发的层级导航块 {current, trail, upUrl}，面包屑全读它。
  // ----------------------------------------------------------
  projectCount: 0,
  currentFolder: null,
  folderId: '',
  folderNav: { current: null, trail: [], upUrl: null },
  filters: {
    query: '',
    members: [],
    headOfProject: '',
    start_date_from: '',
    start_date_to: '',
    due_date_from: '',
    due_date_to: '',
    archived_on_from: '',
    archived_on_to: '',
    statuses: [],
    // 「在文件夹内查找」（原生 "Look inside folders"，
    // projects.index.filters_modal.folders.label → Lists::ProjectsService 的 folder_search）。
    // ⚠ 布尔而不是字符串：只有 true 时才在 query string 里发 `filters[folder_search]=true`
    //   —— 发 `false` 会让服务端 `@filters.present?` 成立，从而**整个并集分支失效**
    //   （文件夹行永远不出现，而页面看不出任何异常）。
    folderSearch: false
  },
  // 列显隐：默认全部可见，键集合由 COLUMN_DEFS 生成（不在这里另抄一份，
  // 免得加列时只改一边 → 新列永远渲染不出来）。
  columnVisibility: Object.fromEntries(COLUMN_KEYS.map((k) => [k, true])),
  // ----------------------------------------------------------
  // 钉列集合（V1.34，取代 V1.33 的 pinnedUpTo 单锚点）
  //
  // 原生语义（shared/datatable/table.vue + modals/columns.vue）：
  //   · **每列独立** pin / unpin，可同时钉住多列（columnsState[].pinned = 'left'）；
  //   · 钉住的列被归拢到表格最左侧（pinned-left 容器），组内保持列序；
  //   · 'checkbox' 列恒钉（selectionColumnDef pinned:'left'，
  //     saveTableState 里还会强制写回），不给图钉。
  //
  // 我们的表格是手写 flex 网格，没有 ag-grid 的 pinned 容器，用两条 CSS 复刻
  // 同样的可观察行为：钉住列 order:0（归拢最左） + position:sticky（滚动不动），
  // 未钉列 order:1。left 偏移 = 前面各钉住可见列的宽度 + gap 累加。
  //
  // ⚠ 数组而不是 Set：reactive 的 Set 变更在 Vue 3 里能响应，但序列化要额外转换，
  //    且与持久化 JSON 的往返形态不一致（第二真源）。数组即真源。
  // ----------------------------------------------------------
  pinned: ['check'],
  foldersOpen: false,
  listLoading: false,
  listError: '',

  // 宿主注入（原型独立跑时全是空值 → 所有网络动作自动退化成空操作）
  listUrl: '',
  createUrls: {},
  folders: [],
  members: [],
  // 「访问权限」弹窗里「添加成员」下拉的**可指派成员**端点（payload 下发）。
  // 空 = 显式留白（下拉只剩占位），不拿原型演示名单冒充真数据。
  assignableUsersUrl: '',
  // 列状态持久化端点基址（V1.33，payload 下发 /user_settings）。
  // 空 = 原型独立跑，列显隐/钉列不持久化（与旧版行为一致）。
  userSettingsUrl: '',
  // 工作台入口（OPEN-WB-7）：项目列表页头那颗「工作台」的真落点，由 payload 下发。
  // 空 = 不渲染按钮（不是渲染出来再置灰），与行菜单同口径。
  workbenchUrl: '',
  headOfProjects: [],
  statuses: [],
  defaultRoles: [],
  // ---------- 下钻地址（宿主注入；空 → 前端回落原型路径，纯退化）----------
  // 这些以前由各视图用原型 SPA 路径现拼（/projects/:id 等），落进 addon 后全是死链。
  // 铁律：前端不写死宿主路由，一律由后端 payload 下发真实 URL。
  projectDetailUrl: '',   // 实验详情面包屑第二级 → 项目详情
  projectListUrl: '',     // 项目详情面包屑第一级 → addon 项目列表页
  listConsumer: null
})

export function setViewRender(v) {
  ui.viewRender = v
}

// ------------------------------------------------------------
// 活动 / 归档：切的是**服务端口径**（原生 view_mode 参数），必须重拉。
//
// 🔴 V1.31：两侧的分页状态必须**各自独立**（spec SCN-PROJ-LIST-13 第 9 条）——
//   在活动视图把每页数调成 50，切到归档不该跟着变，切回活动也不能丢。
//   做法是每个视图留一格，切换时「存旧的 / 取新的」。
//   ⚠ 这一格是**临时**的：票③ 把列表状态搬去服务端（user_settings，key 按
//     eln_project_list_<active|archived>_table_state 分）之后，这里改为
//     从 payload 回填 + 落盘，本内存格随之退场。别在这里长出第二套持久化。
// ------------------------------------------------------------
const paginationByMode = {
  active: { page: 1, perPage: 20 },
  archived: { page: 1, perPage: 20 }
}

/** 把「当前视图」的分页状态记回它自己那一格（切视图 / 改档位 / 翻页时调） */
function rememberPagination() {
  paginationByMode[ui.viewMode] = { page: pageParam(), perPage: perPageParam() }
}

export function setViewMode(v) {
  if (ui.viewMode === v) return
  rememberPagination()
  ui.viewMode = v
  const saved = paginationByMode[v] || { page: 1, perPage: 20 }
  ui.page = saved.page
  ui.perPage = saved.perPage
  clearSelection()
  refreshList()
}

// 顶部搜索框：debounce 后再打服务端，避免每敲一个字一个请求。
let searchTimer = null
export function setQuery(v) {
  ui.query = v
  clearTimeout(searchTimer)
  searchTimer = setTimeout(() => refreshList(), 300)
}

export function toggleSearch() {
  ui.searchOpen = !ui.searchOpen
  if (!ui.searchOpen && ui.query) {
    ui.query = ''
    refreshList()
  }
}

export function setFilter(key, value) {
  ui.filters[key] = value
}

// 列头排序：点一下升序 → 再点降序 → 第三下取消（回到默认）。
// column 取原生 service 的 key（name/code/status/due_date/supervised_by/users/
// completed_experiments），不是我们的列名 —— 排序语义完全交给原生 sort_records。
export function toggleSort(column) {
  if (ui.sort.column !== column) {
    ui.sort = { column, dir: 'asc' }
  } else if (ui.sort.dir === 'asc') {
    ui.sort = { column, dir: 'desc' }
  } else {
    ui.sort = { column: '', dir: '' }
  }
  // 换排序后原页码可能已越界（比如第 8 页、排序后只剩 2 页 → 空列表），
  // 所以排序变更一律回到第 1 页。spec 只规定「翻页不得重置排序」，
  // 反方向（换排序重置页码）是必要的兜底，不是自由发挥。
  ui.page = 1
  rememberPagination()
  return refreshList()
}

// ------------------------------------------------------------
// V1.31 分页动作
//
// 两个入口都必须「清选中 + 重拉」：
//   · 清选中 —— spec SCN-PROJ-LIST-13：全选语义限定**当前页**，批量条计数
//     要与当前页选中数一致。换页后上一页的 id 还留在 selectedProjectIds 里，
//     计数就与眼前这一页对不上了，而且批量操作会打到看不见的行上。
//   · 重拉  —— 页码 / 档位都是**服务端**参数，不重拉等于没改。
//
// 原型独立跑（没注入 listUrl）时 refreshList() 是空操作，只改本地状态 ——
// 与其它工具栏控件同款退化，这里不需要 if (真机) 分支。
// ------------------------------------------------------------
export function setPerPage(n) {
  const v = Math.trunc(Number(n))
  if (!Number.isFinite(v) || v < 0) return false
  if (v === ui.perPage) return false

  ui.perPage = v
  ui.page = 1 // 改档位必须回到第 1 页（spec SCN-PROJ-LIST-13 第 2 条）
  rememberPagination()
  clearSelection()
  return refreshList()
}

export function gotoPage(n) {
  const v = Math.trunc(Number(n))
  if (!Number.isFinite(v) || v < 1) return false
  if (v === ui.page) return false

  ui.page = v
  rememberPagination()
  clearSelection()
  return refreshList()
}

export const EMPTY_FILTERS = {
  query: '',
  members: [],
  headOfProject: '',
  start_date_from: '',
  start_date_to: '',
  due_date_from: '',
  due_date_to: '',
  archived_on_from: '',
  archived_on_to: '',
  statuses: [],
  folderSearch: false
}

export function resetFilters() {
  ui.filters = { ...EMPTY_FILTERS }
}

// 筛选面板「显示结果」：把条件拼成原生认识的 query string 后重拉。
export async function applyFilters() {
  closeFilter()
  return refreshList()
}

export function toggleColumn(key) {
  if (key in ui.columnVisibility) {
    ui.columnVisibility[key] = !ui.columnVisibility[key]
    saveTableState()
  }
}

// ---------------------------------------------------------------------------
// 钉列（V1.34）：每列独立 pin / unpin，可同时钉住多列。
//
// 与原生 columns.vue 的 pinColumn/unPinColumn 同语义：点图钉即在
// 「钉住集合」里增删该列，不影响其它列的状态。多个钉住列在渲染时按
// COLUMN_DEFS 的原序归拢到最左（见 ProjectList.vue 的 pinStyles）。
//
//   · alwaysPinned 列（check）不可取消 —— 直接忽略，不给图钉（UI 上也不渲染），
//     这里是兜底：万一有人从控制台/旧存档塞进来，也钉不歪。
//   · 变更即持久化（对齐原生 table.vue：handlePin 事件里立刻 saveTableState）。
// ---------------------------------------------------------------------------
export function togglePinned(key) {
  if (ALWAYS_PINNED.includes(key)) return
  ui.pinned = ui.pinned.includes(key)
    ? ui.pinned.filter((k) => k !== key)
    : [...ui.pinned, key]
  saveTableState()
}

/** 该列是否钉住（渲染层与列管理菜单共用同一判定，别各写一份） */
export function isPinned(key) {
  return ALWAYS_PINNED.includes(key) || ui.pinned.includes(key)
}

/**
 * 钉列集合归一化：未知键剔除、去重、恒钉列补回、顺序按 COLUMN_DEFS。
 *
 * 为什么必须归一：pinned 是从**服务端 JSON** 读回来的（用户可手改、
 * 也可能是旧版本写的），直接拿来算 sticky 偏移会出现「钉了但偏移算错」
 * 这类最难查的静默错位。顺序按列序重排，保证钉住区的渲染序 == 列序。
 */
export function normalizePinned(list) {
  const set = new Set(Array.isArray(list) ? list : [])
  return COLUMN_KEYS.filter((k) => set.has(k) || ALWAYS_PINNED.includes(k))
}

/**
 * V1.33 旧存档迁移：单锚点 pinnedUpTo → 「锚点及其左侧所有**可见**列」的集合。
 * 不做这层兼容，老用户升级后钉列会**凭空消失**（存档里有值但新代码不认），
 * 属于静默回退 —— 比报错更难发现。
 */
function prefixUpTo(anchor) {
  const i = COLUMN_KEYS.indexOf(anchor)
  if (i < 0) return [...ALWAYS_PINNED]
  // 隐藏列不进钉住集合：它不渲染，钉了也只是占一个偏移位
  return COLUMN_KEYS.slice(0, i + 1).filter((k) => ui.columnVisibility[k] || ALWAYS_PINNED.includes(k))
}

// ============================================================
// 列状态持久化（V1.33，对齐原生 shared/datatable/table.vue 的机制）
//
// 原生口径：列显隐 / 钉住 / 顺序 / 宽度 / 每页条数按用户存**服务端**
//   （GET/PUT /user_settings/:key，通用 per-user KV），跨浏览器、换机器不丢。
// 我们复用同一条端点：key = eln_project_list_table_state，值存
//   { columnVisibility, pinned[] }。URL 基址由 payload 下发
//   （userSettingsUrl）—— 前端不写死宿主路由（铁律）。
// 原型独立跑时 userSettingsUrl 为空 → 直接跳过，行为与旧版一致。
// 端点失败（404 = 从没存过 / 网络异常）静默降级为默认值，与原生 catch 同款。
// ============================================================
export const TABLE_STATE_KEY = 'eln_project_list_table_state'

export async function fetchTableState() {
  if (!ui.userSettingsUrl) return
  const res = await fetch(`${ui.userSettingsUrl}/${TABLE_STATE_KEY}`, {
    headers: { Accept: 'application/json' },
    credentials: 'same-origin'
  })
  if (!res.ok) return // 404 = 还没存过；其他 = 异常。两者都用默认值。
  const data = await res.json()
  const value = data && data.value
  if (!value || typeof value !== 'object') return
  if (value.columnVisibility && typeof value.columnVisibility === 'object') {
    // 只合并已知键：未来加新列时，旧存档里没有的键保持默认 true
    Object.keys(ui.columnVisibility).forEach((k) => {
      if (typeof value.columnVisibility[k] === 'boolean') {
        ui.columnVisibility[k] = value.columnVisibility[k]
      }
    })
  }
  // 钉列：V1.34 起是数组（多列）；旧存档是 V1.33 的单锚点 pinnedUpTo。
  // 两种都认 —— 旧值经 prefixUpTo 转成等价的前缀集合，升级不丢状态。
  if (Array.isArray(value.pinned)) {
    ui.pinned = normalizePinned(value.pinned)
  } else if (typeof value.pinnedUpTo === 'string') {
    ui.pinned = normalizePinned(prefixUpTo(value.pinnedUpTo))
  }
}

let saveStateTimer = null
export function saveTableState() {
  if (!ui.userSettingsUrl) return
  // 轻防抖：勾一列/钉一列是连续点击场景，别一发一个请求
  clearTimeout(saveStateTimer)
  saveStateTimer = setTimeout(async () => {
    try {
      await fetch(`${ui.userSettingsUrl}/${TABLE_STATE_KEY}`, {
        method: 'PUT',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken()
        },
        body: JSON.stringify({
          user_setting: {
            // 存的时候也归一：钉住区顺序恒等于列序，读回来不需要再猜
            value: {
              columnVisibility: { ...ui.columnVisibility },
              pinned: normalizePinned(ui.pinned)
            }
          }
        })
      })
    } catch (e) {
      // 存不上不影响功能：本次会话内状态仍在，只是刷新后回默认
    }
  }, 300)
}

export function openFolders() {
  ui.foldersOpen = true
}
export function closeFolders() {
  ui.foldersOpen = false
}

// ============================================================
// 网络层（只有挂进 SciNote 才真的发请求）
//
// CSRF：addon 的 index.html.erb 单独吐了 <meta name="csrf-token">，
// 原生 projects#create 是 POST 且开了 protect_from_forgery，不带 token 直接 422。
// ============================================================
function csrfToken() {
  const el = document.querySelector('meta[name="csrf-token"]')
  return el ? el.getAttribute('content') : ''
}

// 条件 → 原生 query string。
// ⚠ 键名必须与原生 Lists::ProjectsService#filter_project_records 一一对应：
//   view_mode            活动 / 归档
//   search               顶部搜索（走 where_attributes_like）
//   filters[query]       筛选面板「包含文本」
//   filters[members][]   成员（joins user_assignments）
//   filters[head_of_project]
//   filters[start_date_from|to] / filters[due_date_from|to]
//   filters[archived_on_from|to]（仅归档态）
//   filters[statuses][]  not_started / in_progress / done（不是状态 id！）
export function buildListQuery() {
  const p = new URLSearchParams()
  p.set('view_mode', ui.viewMode || 'active')
  if (ui.query) p.set('search', ui.query)

  const f = ui.filters || {}
  if (f.query) p.set('filters[query]', f.query)
  ;(f.members || []).forEach((id) => p.append('filters[members][]', id))
  if (f.headOfProject) p.set('filters[head_of_project]', f.headOfProject)
  ;[
    'start_date_from',
    'start_date_to',
    'due_date_from',
    'due_date_to',
    'archived_on_from',
    'archived_on_to'
  ].forEach((k) => {
    if (f[k]) p.set(`filters[${k}]`, f[k])
  })
  ;(f.statuses || []).forEach((s) => p.append('filters[statuses][]', s))
  // 「在文件夹内查找」（原生 folder_search）。
  // 🔴 **只在为 true 时发出**，绝不能发 `false`：服务端 `Lists::ProjectsService#call`
  //   判断的是 `@filters.present?` —— 一旦 filters 里出现任何一个键（哪怕是 false），
  //   就落到「只出项目行」那条分支，文件夹行从此永远不显示，而页面 200、无任何报错。
  if (f.folderSearch === true) p.set('filters[folder_search]', 'true')
  // 当前文件夹层级（原生 `project_folder_id`，与原生 projects#index 同名同义）。
  // ⚠ 必须带上：不带的话每次翻页/排序/筛选都会**静默退回顶层**（用户以为只是排序，
  //   结果发现自己出了文件夹），且服务端 200、前端无异常。
  if (ui.folderId) p.set('project_folder_id', String(ui.folderId))
  // 排序：原生 base_service.require(:order).permit(:column, :dir)，非 asc 一律按 DESC
  if (ui.sort && ui.sort.column) {
    p.set('order[column]', ui.sort.column)
    p.set('order[dir]', ui.sort.dir === 'desc' ? 'desc' : 'asc')
  }
  // 分页：参数名与原生**逐字一致**（原生 Lists::BaseService#paginate_records 读的
  // 就是 params[:page] / params[:per_page]，别自造 p / size 之类的别名）。
  // ⚠🔴 per_page **必须原样发出，即使是 0**：0 是合法值（= 全部），
  //   若写成 `if (ui.perPage) p.set(...)` 这种真值判断，0 会被吃掉 →
  //   服务端按「为空」回落成 20 → 用户明明选了「全部」却只看到 20 条，
  //   而页面没有任何提示（本轮最容易踩的静默失效）。
  p.set('page', String(pageParam()))
  p.set('per_page', String(perPageParam()))
  return p.toString()
}

// 页码 / 档位归一化（与后端 ProjectListPayload.normalize_page / normalize_per_page 同规则：
// 非法值前端自己也兜一层，避免发出 page=NaN 这种让服务端白算一次的请求）。
function pageParam() {
  const n = Math.trunc(Number(ui.page))
  return Number.isFinite(n) && n >= 1 ? n : 1
}

function perPageParam() {
  const n = Math.trunc(Number(ui.perPage))
  return Number.isFinite(n) && n >= 0 ? n : 20
}

// 统一的列表刷新入口：组件只管调它，具体怎么拉、拉回来写哪由 entry 决定。
// 没注入 listUrl（原型独立跑）就是空操作，不去打扰本地 mock。
export async function refreshList() {
  if (!ui.listUrl) return false
  ui.listLoading = true
  ui.listError = ''
  try {
    const sep = ui.listUrl.includes('?') ? '&' : '?'
    const res = await fetch(`${ui.listUrl}${sep}${buildListQuery()}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin'
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const data = await res.json()
    if (typeof ui.listConsumer === 'function') ui.listConsumer(data)
    return true
  } catch (e) {
    ui.listError = e && e.message ? e.message : '刷新失败'
    return false
  } finally {
    ui.listLoading = false
  }
}

async function postForm(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken()
    },
    body: JSON.stringify(body)
  })
  const text = await res.text()
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch (_) {
    data = null
  }
  if (!res.ok) {
    // 原生校验失败回的是 { name: ['不能为空'] } 这种错误哈希，取第一条给人看。
    const msg =
      (data && typeof data === 'object' && Object.values(data)[0]) ||
      `HTTP ${res.status}`
    throw new Error(Array.isArray(msg) ? msg.join('，') : String(msg))
  }
  return data
}

/**
 * 新建项目 → POST 原生 /projects。
 *
 * 只发原生真有的字段（projects#create 的 project_params 白名单）：
 *   name / start_date / due_date / description / project_folder_id
 *   default_public_user_role_id（全队默认角色；为空 = 只给显式指派的人可见）
 *
 * ⚠ 原型弹窗里的「可见性」不是原生字段 —— 它其实由 default_public_user_role_id
 *   是否为空表达：留空 = 仅项目成员可见，设成角色 = 全队按该角色可见。
 *   所以这里按可见性开关决定要不要把角色 id 发出去，不编一个原生不存在的列。
 */
/**
 * 通用原生写端点调用（行菜单 7 项里的「直调型」就走这一个出口：
 * 编辑 PATCH /projects/:id、移动 PATCH、导出 POST、归档 POST）。
 *
 * ⚠ 为什么不用 postForm 直接改名：postForm 里写死 method: 'POST'，
 *   而 projects#update / project_folders#move_to 这类是 PATCH，
 *   发成 POST 原生会直接 404（本 addon 里没有"传 method 参数"的后端）。
 *
 * 端点 URL 一律由 payload 下发（row.actions.xxx.url），这里不拼宿主义定路径。
 */
export async function sendForm(url, method, body) {
  if (!url) throw new Error('缺少原生端点 URL（payload 未下发）')
  const res = await fetch(url, {
    method,
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken()
    },
    body: JSON.stringify(body || {})
  })
  const text = await res.text()
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch (_) {
    data = null
  }
  if (!res.ok) {
    const msg =
      (data && typeof data === 'object' && (data.message || data.flash || Object.values(data)[0])) ||
      `HTTP ${res.status}`
    throw new Error(Array.isArray(msg) ? msg.join('，') : String(msg))
  }
  return data
}

export async function createProject(form) {
  if (!ui.createUrls || !ui.createUrls.project) {
    closeNewProject()
    return false
  }
  const payload = {
    name: form.name,
    start_date: form.start || '',
    due_date: form.due || '',
    description: form.desc || '',
    // 归入哪个文件夹：弹窗里显式选了就用它；没选时若**当前正处在某文件夹层级内**，
    // 则默认建在当前层（原生 NewProjectModal 同款 —— 在文件夹里点「新建项目」，
    // 建完必须出现在眼前这一层，而不是悄悄跑到顶层然后"看不见"）。
    project_folder_id: form.folderId || ui.folderId || ''
  }
  if (form.visibility === 'team' && form.roleId) {
    payload.default_public_user_role_id = form.roleId
  }
  await postForm(ui.createUrls.project, { project: payload })
  closeNewProject()
  await refreshList()
  return true
}

/** 新建文件夹 → POST 原生 /project_folders（强参数 project_folder[name|parent_folder_id|archived]）。 */
export async function createFolder(form) {
  if (!ui.createUrls || !ui.createUrls.folder) {
    closeNewFolder()
    return false
  }
  await postForm(ui.createUrls.folder, {
    project_folder: {
      name: form.name,
      parent_folder_id: form.parentId || null,
      archived: ui.viewMode === 'archived'
    }
  })
  closeNewFolder()
  await refreshList()
  return true
}

// 轻提示（对齐原型 toast）：未展开的原生入口须有明确反馈（SCN-NAV-4）
export const toast = reactive({ visible: false, text: '' })
let toastTimer = null
export function showToast(text, duration = 2400) {
  toast.text = text
  toast.visible = true
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    toast.visible = false
  }, duration)
}

export function openNavigator() {
  ui.navigatorOpen = true
}
export function closeNavigator() {
  ui.navigatorOpen = false
}
export function openNewProject() {
  ui.newProjectOpen = true
}
export function closeNewProject() {
  ui.newProjectOpen = false
}
export function openNewFolder() {
  ui.newFolderOpen = true
}
export function closeNewFolder() {
  ui.newFolderOpen = false
}
export function openFilter() {
  ui.filterOpen = true
}
export function closeFilter() {
  ui.filterOpen = false
}
/**
 * 打开行菜单。
 * @param items 菜单项数组；不传 = 默认 8 项（原型独立跑 / payload 没下发 actions）。
 *              真机上由 ProjectList 传「payload 算出来的那一份」——
 *              没有权限的项**不出现**（照原生 actions_toolbar 的 compact 语义）。
 */
export function openRowMenu(target, x, y, items) {
  ui.rowMenuTarget = target
  ui.rowMenuPos = { x, y }
  ui.rowMenuItems = Array.isArray(items) && items.length ? items : rowMenuItems
  ui.rowMenuOpen = true
}

/** 打开行动作浮层：kind ∈ edit | move | access | comment */
export function openRowAction(kind, row) {
  ui.rowAction = { kind, row }
}
export function closeRowAction() {
  ui.rowAction = null
}

// ---------------------------------------------------------------------------
// 行操作菜单项（components/overlays/RowMenu.vue 消费）
//
// 原生口径（Lists::ProjectsService / projects_service.rb）：活动项目行菜单 7 项，
// 无「删除」。我们按**下钻落地**的需要在原生 7 项**之前**插入「打开项目详情」——
// 它是行菜单最常用的一条，也是「菜单路径下钻」唯一入口。
//
// 🔴 原样 7 项里没有下钻项，光有菜单等于点了没反应（此前 RowMenu.vue 就停在
//    状态有、DOM 有、动作无的阶段）。action 由 ProjectList 按 key 分发。
// ---------------------------------------------------------------------------
export const rowMenuItems = [
  { key: 'open', label: '打开项目详情', icon: 'eye' },
  { key: 'edit', label: '编辑', icon: 'edit' },
  { key: 'access', label: '访问权限', icon: 'users' },
  { key: 'move', label: '移动', icon: 'folder' },
  { key: 'export', label: '导出', icon: 'export' },
  { key: 'archive', label: '归档', icon: 'archive' },
  { key: 'comment', label: '评论', icon: 'comment' },
  { key: 'activity', label: '动态', icon: 'activity' }
]

/**
 * 文件夹行的菜单项（V1.32 / spec SCN-PROJ-LIST-7 第 6 条）。
 *
 * 🔴 这是**文件夹专属集合**，与上面项目行的 8 项**互不混用**：
 *   不得出现「访问权限 / 归档 / 评论 / 动态」（那是项目独有的动作），
 *   也不得出现「导出」—— 原生 `Toolbars::ProjectsService#export_action` 虽然
 *   对文件夹也开（它把文件夹当"内部项目"整体导出），但那条路径要求把
 *   `project_folder_ids` 与 `project_ids` 一起发给 `/teams/:id/export_projects`，
 *   属于批量条（SCN-PROJ-LIST-10）的事，不塞进行菜单，免得长出一个半成品入口。
 *   「打开」在这里的落点不是项目详情，而是**进入该文件夹层级**（drillUrl）。
 */
export const folderRowMenuItems = [
  { key: 'open', label: '打开文件夹', icon: 'folder' },
  { key: 'edit', label: '编辑', icon: 'edit' },
  { key: 'move', label: '移动', icon: 'folder' },
  { key: 'delete', label: '删除', icon: 'trash' }
]

/**
 * 行菜单「原生存量 7 项」的 key ↔ 前端落点类型。
 *   modal —— 由 RowActionModal 承载四种浮体（edit/access/move/comment）
 *   post  —— 直接 POST 原生批量端点（原生这俩就是批量 action：archive_group / export_projects）
 *   link  —— 原生 activities_action 是 type: :link，直接跳
 * 🔴 权限 gate 不在前端判（那会是第二套口径）：payload 已按原生 Canaid 谓词算好
 *    并 compact 掉没权限的项，这里只负责「enabled 的项该以哪种方式落地」。
 */
export const ROW_ACTION_KINDS = {
  edit: { kind: 'modal' },
  access: { kind: 'modal' },
  move: { kind: 'modal' },
  comment: { kind: 'modal' },
  // 文件夹删除（V1.32）：走 modal —— 它是**破坏性**动作，必须先确认再发请求。
  // 不做成 'post' 直发：'post' 那条路的 body 固定是 `{project_ids:[id]}`，
  // 而原生 project_folders#destroy 收的是 `project_folder_ids`，发错键会静默 0 删除
  // 之后回一个 422（"删除失败"），用户永远不知道为什么。
  delete: { kind: 'modal' },
  export: { kind: 'post' },
  archive: { kind: 'post' },
  activity: { kind: 'link' }
}
export function closeRowMenu() {
  ui.rowMenuOpen = false
}

export function toggleProjectSelection(id) {
  const i = ui.selectedProjectIds.indexOf(id)
  if (i === -1) ui.selectedProjectIds.push(id)
  else ui.selectedProjectIds.splice(i, 1)
  ui.bulkBarVisible = ui.selectedProjectIds.length > 0
}
export function clearSelection() {
  ui.selectedProjectIds = []
  ui.bulkBarVisible = false
}
