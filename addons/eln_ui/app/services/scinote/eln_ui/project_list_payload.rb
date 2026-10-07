# frozen_string_literal: true

# ELN UI —— 项目列表页的**真实**数据装配
#
# 与 ProjectDetailPayload 的分工：
#   详情页 Service 负责「一个项目往里看」（项目概况 / 成员 / 实验）；
#   列表页 Service 负责「一层往平看」（项目卡片行 + 建项目按钮的权限）。
#   两边都不碰 view / controller，addon 测试可以直接测 Service。
#
# 口径（与详情页同一条规矩：不编造）：
#   - 「项目编号」：原型演示值是 PR1025240 这种业务编号；projects 表没有这列，
#     这里给主键字符串（列头就是 ID，下游渲染成纯数字）。
#   - 「项目来源 / 项目状态（立项中·年度考核·结题中）」：原生只有三态三列
#     （started_at / done_at / archived），比 PRD 的 5 态粗。这里**按原生三态映射**，
#     不造 5 态（要造得加字段，那属于规格侧的事，已记 OPEN）。
#   - 「可见范围」：不做第二套过滤 —— 复用原生 PermissionCheckableModel 的
#     readable_by_user（与 access_control D8「同源同层」同原则，见 controller）。
#     列表里出现的项目 == 用户能读的项目，SCN-PROJ-LIST-1/2/3 由此落到原生语义上。
#   - 「行菜单 7 项」（编辑/访问权限/移动/导出/归档/评论/动态）：真源口径**照抄原生
#     Toolbars::ProjectsService**（原生项目列表行行动的唯一权威定义）。它把每个动作
#     的 gate（can_manage_project? / can_manage_team? / can_archive_project? /
#     can_export_project? / can_read_project?）和 path 一起算完，compact 掉没权限的。
#     这里不等价地重写一遍，而是**沿用同一批 Canaid 谓词 + 同一组 path helper**，
#     保证「前端菜单里出现什么」与「原生 /projects 行菜单出现什么」逐项一致。
#     ⚠ 不能照抄它的 action 列表输出：原生那 8 项里有 restore / delete_folders 是
#       **批量/文件夹专用**（项目行不该出现），而且它的 path 语义是「发给 actions_toolbar
#       再回一套 descriptor」，中间要过一次 POST + JSON，payload 是纯读服务，走不通。
#
# 字段名一一对应原型的 mock（src/data/mock.js 的 projects 数组）：
#   { id, name, starred, status, due, owner:{name,initial,color},
#     completed, total, members:[{initial,color}], extra }

module Scinote
  module ElnUi
    class ProjectListPayload
      # 行菜单 7 项的 key（与前端 store/ui.js #rowMenuItems 一一对应）
      ACTION_KEYS = %i[edit access move export archive comment activity].freeze

      # ------------------------------------------------------------
      # V1.31 分页档位 —— **本常量是档位唯一真源**，随 payload 下发给前端。
      #
      # `0` 是**合法值**，语义 = 全部（不分页）：
      #   选 0 时服务端一次返回筛选后的全部行，前端不渲染页码控件。
      #   为什么把 0 放在档位里而不是另做一个「显示全部」开关：它与 20/50/100
      #   是同一个决策轴上的取值（每页几条），做成两个控件会出现
      #   「档位选 50 + 开关说显示全部」这种自相矛盾的状态。
      # ⚠ 默认档位是 20（不是 0）：默认全量会把几百行一次塞进 DOM，
      #   首屏与后续排序都变慢，而 20 是原生既有的默认。
      #
      # 档位只能在这里加/减 —— 前端从 `pagination.perPageOptions` 渲染，
      # 不在组件里写死第二份（本项目「同一事实只许一个真源」铁律）。
      # ------------------------------------------------------------
      PER_PAGE_OPTIONS = [0, 20, 50, 100].freeze
      DEFAULT_PER_PAGE = 20

      # 非法 per_page（非整数 / 不在档位里 / 为空）的回落值。
      # ⚠ 回落成 **DEFAULT_PER_PAGE 而不是 0**：spec SCN-PROJ-LIST-13 明令
      #   「不得退化为全量返回」（全量会让前端页码控件失真）。
      #   也就是说 0 **只有显式请求**才生效 —— 乱传参数不会意外拖库。
      def self.normalize_per_page(raw)
        return DEFAULT_PER_PAGE if raw.blank?

        value = Integer(raw.to_s, exception: false)
        return DEFAULT_PER_PAGE if value.nil?

        PER_PAGE_OPTIONS.include?(value) ? value : DEFAULT_PER_PAGE
      end

      # 页码：非整数 / 小于 1 / 为空一律当第 1 页（不报错、不返回空页）。
      def self.normalize_page(raw)
        return 1 if raw.blank?

        value = Integer(raw.to_s, exception: false)
        value.nil? || value < 1 ? 1 : value
      end

      # 无用户上下文时的行行动（原型独立跑 / 测试里没传 current_user）：
      # 每一项都是 enabled: false —— 菜单照渲染但点不动，绝不按演示值假装可用。
      NO_USER_ACTIONS = ACTION_KEYS.each_with_object({}) do |k, h|
        h[k] = { enabled: false, method: 'GET', url: nil }
      end.freeze

      # 文件夹行的行动 key 集合（文件夹**专属**，与项目行的 7 项互不混用，
      # spec SCN-PROJ-LIST-7 第 6 条）。无用户上下文时全部 enabled: false。
      FOLDER_ACTION_KEYS = %i[edit move delete].freeze

      NO_USER_FOLDER_ACTIONS = FOLDER_ACTION_KEYS.each_with_object({}) do |k, h|
        h[k] = { enabled: false, method: 'GET', url: nil }
      end.freeze

      # 🔴 Canaid 的 can_*? 全部走 method_missing（见 canaid/helpers/permissions_helper.rb），
      #    挂在 Service 上时没有 controller 的 current_user，必须自己定义（见 #current_user）。
      include Canaid::Helpers::PermissionsHelper

      # 原型头像配色（avatarPalette 的 5 个 key），按下标轮转，保证同一列表里稳定。
      AVATAR_COLORS = %w[blue green orange cyan purple].freeze
      # 用户组授予头像用的配色键（与 avatarPalette 同源；组用图标区分，不靠颜色）。
      GROUP_AVATAR_COLOR = 'blue'

      # ⚠ 原型 statusLabel 只有这三档（active/notstarted/done），真机也按这三档给出，
      #   由组件侧的 mock.statusLabel 翻译成中文（进行中 / 未开始 / 已完成）。
      #   状态本身是**原生推导**的，不是枚举列 —— 见 status_of。
      DATE_FMT = '%Y-%m-%d'
      DATETIME_FMT = '%Y-%m-%d %H:%M'

      # V1.27：深链筛选条件里「日期类」的键（与前端 store/ui.js 的 EMPTY_FILTERS 对齐）。
      # 这几个原样传字符串即可（FilterPanel 用的是 <input type="date">，值是字符串）。
      INITIAL_DATE_FILTER_KEYS = %w[
        start_date_from start_date_to due_date_from due_date_to
        archived_on_from archived_on_to
      ].freeze

      # 工具栏（原生 toolbar.vue 那 7 个控件）需要的全部能力，都在 payload 里出一份：
      #   canCreateFolder —— 「新建文件夹」按钮（原生 TeamPermissions::CREATE_PROJECT_FOLDERS）
      #   folders/members/headOfProjects/statuses/defaultRoles —— 筛选面板/新建弹窗的可选项
      #   createUrls      —— 新建项目/文件夹的原生 POST 端点（前端不写死宿主路由）
      #   listUrl         —— json 出口（按钮改完条件后只重拉数据，不整页重载）
      #   viewMode        —— 当前活动/归档（首屏与刷新后保持一致）
      #   rowActions      —— 行菜单 7 项（编辑/访问权限/移动/导出/归档/评论/动态）的
      #                      权限 + 端点，见下方 row_actions 的映射表。
      # 全部带默认值，老调用方（含 addon 测试）不传也能跑，不会被这一步打断。
      class << self
        def call(projects, can_create_project: false, can_create_folder: false,
                 folders: [], members: [], head_of_projects: [], statuses: [],
                 default_roles: [], create_urls: {}, list_url: nil, view_mode: 'active',
                 detail_url_base: nil, current_user: nil, workbench_url: nil,
                 option_errors: [], initial_filters: {},
                 page: 1, per_page: DEFAULT_PER_PAGE, total_entries: nil,
                 project_count: nil, current_folder: nil, folder_trail: [],
                 folder_url_base: nil)
          new(projects,
              can_create_project: can_create_project,
              can_create_folder: can_create_folder,
              folders: folders,
              members: members,
              head_of_projects: head_of_projects,
              statuses: statuses,
              default_roles: default_roles,
              create_urls: create_urls,
              list_url: list_url,
              view_mode: view_mode,
              detail_url_base: detail_url_base,
              current_user: current_user,
              workbench_url: workbench_url,
              option_errors: option_errors,
              initial_filters: initial_filters,
              page: page,
              per_page: per_page,
              total_entries: total_entries,
              project_count: project_count,
              current_folder: current_folder,
              folder_trail: folder_trail,
              folder_url_base: folder_url_base).call
        end
      end

      def initialize(projects, can_create_project: false, can_create_folder: false,
                     folders: [], members: [], head_of_projects: [], statuses: [],
                     default_roles: [], create_urls: {}, list_url: nil, view_mode: 'active',
                     detail_url_base: nil, current_user: nil, workbench_url: nil,
                     option_errors: [], initial_filters: {},
                     page: 1, per_page: DEFAULT_PER_PAGE, total_entries: nil,
                     project_count: nil, current_folder: nil, folder_trail: [],
                     folder_url_base: nil)
        # ⚠ V1.32 起第一个位置参数是**行集合**（项目行 ∪ 文件夹行），不是纯项目数组 ——
        #   名字沿用 `projects` 只为不惊动既有调用方，语义见 `rows_block`。
        @projects = projects.to_a
        @current_user = current_user
        @can_create_project = can_create_project
        @can_create_folder = can_create_folder
        @folders = Array(folders)
        @members = Array(members)
        @head_of_projects = Array(head_of_projects)
        @statuses = Array(statuses)
        @default_roles = Array(default_roles)
        @create_urls = create_urls.is_a?(Hash) ? create_urls : {}
        @list_url = list_url
        @detail_url_base = detail_url_base.presence && detail_url_base.to_s.chomp('/')
        @view_mode = view_mode.to_s.presence || 'active'
        # 工作台入口（OPEN-WB-7）。之前宿主左菜单 11 项里一个 /eln_workbench 都没有，
        # 工作台只能靠直输 URL 进；这里把落点从服务端下发，前端不写死宿主路由。
        # 与 detailUrlBase 同款坑：本 controller 里 url_for 会踩 _recall 那个
        # ActionController::UrlGenerationError，所以用字面基址，路由段与
        # config/routes.rb 的 'eln_workbench' 对齐。
        @workbench_url = workbench_url
        @option_errors = Array(option_errors)
        # V1.27（OPEN-WB-DRILL-8）：本次请求的筛选条件（controller 已转成普通 Hash）。
        @initial_filters = initial_filters.is_a?(Hash) ? initial_filters : {}
        # V1.31 分页：档位/页码都已在 controller 侧归一化（这里再兜一次，防老调用方乱传）。
        @per_page = self.class.normalize_per_page(per_page)
        @page = self.class.normalize_page(page)
        # ⚠ `total_entries` 是**筛选后**的总条数（分页前），不是当前页行数、也不是全库总数。
        #   不传（老调用方 / 单测直接塞数组）时退化为「本次传进来的行数」——
        #   语义正确：那种调用没有分页，传进来的就是全部。
        @total_entries = total_entries.nil? ? @projects.size : total_entries.to_i
        # V1.32：`project_count` = 同一行集合里的**项目行**条数（文件夹行不计）。
        # 为什么不复用 @total_entries：并集后「共 N 条」含文件夹行，而页头副标题
        # 「共 N 个项目」与工作台「参与项目」卡片数字要求的都是**纯项目数**
        # （spec SCN-DASH-8 同源不变式）—— 两个数字必须分开，不能一个顶两个用。
        @project_count = project_count.nil? ? @projects.count { |r| project_row?(r) } : project_count.to_i
        # V1.32 文件夹层级（SCN-PROJ-LIST-7 第 4 条）：当前所在文件夹 / 祖先链 / 下钻基址。
        @current_folder = current_folder
        @folder_trail = Array(folder_trail)
        @folder_url_base = folder_url_base.presence && folder_url_base.to_s.chomp('/')
      end

      def call
        {
          canCreateProject: @can_create_project,
          canCreateFolder: @can_create_folder,
          folders: @folders,
          members: @members,
          headOfProjects: @head_of_projects,
          statuses: @statuses,
          defaultRoles: @default_roles,
          # 筛选项取数失败的项（正常恒为 []）。非空 = 页面上那些下拉是真的拿不到数据，
          # 前端必须显式提示，不能让人以为「就是没数据」。
          filterOptionErrors: @option_errors,
          createUrls: @create_urls,
          listUrl: @list_url,
          viewMode: @view_mode,
          # V1.27（OPEN-WB-DRILL-8）：本次请求已生效的筛选条件（归一化，键与 ui.filters 一致）。
          # 前端 entry 在挂载时 Object.assign(ui.filters, initialFilters) —— 让深链条件
          # 「面板可见 + 重拉不丢」。没条件时是 {}（前端 assign 为空 = 不变）。
          initialFilters: normalized_initial_filters,
          # 行菜单「访问权限」弹窗里的「添加成员」下拉：**可指派成员**端点真源。
          # 没有它，下拉就只剩一个「选择成员…」占位 —— 那是显式留白，不是 bug，
          # 但既然原生有真端点，就别让这个入口点不动。
          assignableUsersUrl: assignable_users_path_of,
          # 工作台入口（OPEN-WB-7）：工作列表页头那颗「工作台」按钮的真落点。
          # 空 = 不渲染按钮（不是渲染出来再置灰），与行菜单同口径。
          workbenchUrl: @workbench_url,
          # V1.31：分页状态（页码 / 档位 / 档位可选集 / 筛选后总条数 / 总页数）。
          # 前端渲染信息条与页码控件全靠它 —— 前端**不得**用 projects.length
          # 当「共 N 条」（分页后那只是当前页行数）。
          #
          # ⚠ V1.32：`totalEntries` 是**行集合**条数（含文件夹行），与页头
          #   「共 N 个项目」用的 `projectCount` 是两个数。见下方 projectCount 注释。
          pagination: pagination_block,
          # V1.32：纯项目行数（筛选后、分页前）。页头副标题用它，**不是** totalEntries。
          projectCount: @project_count,
          # V1.32：文件夹层级导航（SCN-PROJ-LIST-7 第 4 条「进入文件夹层级并提供返回上一层的入口」）。
          # 全空 = 当前在顶层，前端不渲染面包屑（不是渲染一条空的）。
          folderNav: folder_nav_block,
          # 行集合：项目行 ∪ 文件夹行，**服务端排好序**（顺序即原生 sort_records 的结果），
          # 前端按原序渲染、不得重排。
          projects: projects_block
        }
      end

      private

      # ------------------------------------------------------------
      # V1.31 分页块
      #
      # 为什么必须下发 totalEntries 而不是让前端数 projects.length：
      #   分页生效后 `projects` 只是**当前页**的行，用它当「共 N 条」会写出
      #   「共 20 条」这种明显错的数字，页码控件也无从生成
      #   （spec SCN-PROJ-LIST-13 明令「不得由前端对全量数据切片来假装分页」）。
      #
      # ⚠ totalEntries 是**筛选后**的总数：前端翻页 / 改档位都发生在同一筛选下，
      #   它必须跟着筛选走；「库里一共多少」是另一个数，本页不展示。
      # ⚠ perPage = 0（全部）时 totalPages 固定为 1 —— 此时没有"下一页"可言，
      #   前端据此不渲染页码控件（见 showPager）。
      # ------------------------------------------------------------
      def pagination_block
        per = @per_page.to_i
        total = @total_entries.to_i
        total_pages = per.zero? ? 1 : [(total.to_f / per).ceil, 1].max

        {
          page: @page,
          perPage: per,
          perPageOptions: PER_PAGE_OPTIONS,
          totalEntries: total,
          totalPages: total_pages
        }
      end

      # ------------------------------------------------------------
      # 行集合（V1.32）：项目行 ∪ 文件夹行，同一数组、同一形状、按类型分流。
      #
      # 为什么是**一个数组**而不是两个（`projects` + `foldersRows`）：
      #   服务端已按原生 `sort_records` 把两类混排好，两个数组会丢掉「谁在谁前面」
      #   这个信息（文件夹可能夹在项目行中间）。这与原生同构 —— 原生 datatable 的
      #   `rowData` 也是一个数组，用 `Lists::ProjectAndFolderSerializer#folder` 这个
      #   **布尔字段**区分两类行。这里同名字段 `folder`，前端也据此分流。
      #
      # ⚠ 文件夹行**也带全了项目侧的字段**（`members: []` / `owner: 占位` / 计数 0 …），
      #   这是**故意**的防御：模板里任何一处漏写 `v-if="!row.folder"` 的取值都会渲染成
      #   空白，而不是 `undefined.slice(...)` 之类的整页 TypeError。
      #   但它**不构成"假装有数据"** —— 文件夹行自己的单元格都另有 `v-if` 守卫，
      #   真正的项目专属单元格根本不会用到这些占位值。
      # ------------------------------------------------------------
      def projects_block
        @projects.map.with_index do |record, i|
          project_row?(record) ? project_row(record, i) : folder_row(record)
        end
      end

      # 判别**只认 `instance_of?`**（与原生 `Lists::ProjectsService#project?` 同款）。
      # ⚠ 不能用 `is_a?(::Project)`：宿主有 STI/装饰器的话子类会被当成项目行；
      #   也不能用 `respond_to?(:projects_count)` 之类 —— 两边都 respond_to 一堆同名方法。
      def project_row?(record)
        record.instance_of?(::Project)
      end

      def project_row(project, index)
        stats = stats_for(project.id)
        members = members_for(project)

        {
          # 原型 id 是业务编号（PR1025240）；原生没这列 → 用主键，不编业务编号。
          #
          # 🔴 V1.32：`id` 与 `code` 是**两个独立字段**，不得互换、不得互相推导
          #   （spec SCN-PROJ-LIST-8 第 4 条）：
          #     · `id`   —— 数字主键。下钻/选中集合/行请求参数/批量 body 一律用它；
          #     · `code` —— 显示值，`PrefixedIdModel#code` = `PR<id>`，只在 ID 列显示、
          #                 以及被原生 `where_attributes_like` 的关键词搜索命中。
          #   ⚠ 别写成 `code.delete_prefix('PR')` 反过来求 id —— 那是推导，前缀规则一改就崩。
          id: project.id.to_s,
          code: project_code(project),
          # 行类型判别字段（原生 `Lists::ProjectAndFolderSerializer#folder` 同名字段）。
          folder: false,
          name: project.name.to_s,
          # 原生没有项目级收藏列 → 恒 false（组件渲染灰星，不假装已收藏）。
          starred: false,
          status: status_of(project),
          startDate: date(project.respond_to?(:start_date) ? project.start_date : nil),
          due: date(project.respond_to?(:due_date) ? project.due_date : nil),
          owner: owner_of(project, index),
          # ---------- 并集补齐：原生 /projects 表格全列 ----------
          # 实验数与任务数**照抄原生 Lists::ProjectsService#fetch_projects 的 SQL 口径**：
          #   实验 = archived = FALSE；已完成实验 = 非归档 AND done_at IS NOT NULL
          #   任务 = 非归档实验下的非归档 my_module
          #   已完成任务 = 上述任务里 my_module_status_id = 默认流程的 final_status
          # 之前这里用的是 project.experiments（含归档），与原生表格对不上 —— 已统一。
          completed: stats[:completed_experiments],
          total: stats[:experiments],
          tasksCompleted: stats[:completed_tasks],
          tasksTotal: stats[:tasks],
          commentsCount: stats[:comments],
          description: description_of(project),
          createdAt: datetime(project.respond_to?(:created_at) ? project.created_at : nil),
          updatedAt: datetime(project.respond_to?(:updated_at) ? project.updated_at : nil),
          archivedOn: date(project.respond_to?(:archived_on) ? project.archived_on : nil),
          # ---------- 下钻（前端绝不写死宿主路由）----------
          # 原型里是 router-link :to="`/projects/${p.id}`"（原型 SPA 内部路径），
          # 落进 addon 后必须指向**宿真实路由** /projects/:id/eln_project_detail，
          # 否则点进去是404。取不到就nil，前端回落原型路径（纯退化，不假装通）。
          detailUrl: @detail_url_base ? "#{@detail_url_base}/#{project.id}/eln_project_detail" : nil,
          # 项目当前所在的文件夹（原生 projects.project_folder_id）。
          # 下发给前端是为了让「移动」弹窗知道**起点在哪**（好做往返，也避免
          # 一个原本在文件夹里的项目被误判成"本来就在顶层"）。
          folderId: project_folder_id_of(project),
          members: members.first(3),
          extra: [members.size - 3, 0].max,
          # 行菜单 7 项的真源（gate + 原生端点，前端照此渲染/分发）
          actions: row_actions(project)
        }
      end

      # ------------------------------------------------------------
      # 文件夹行（spec SCN-PROJ-LIST-7 / SCN-PROJ-LIST-8）
      #
      # 显示什么：文件夹图标（前端按 `folder: true` 出）+ 名称 + `PF<id>` + 「x 个项目 | y 个文件夹」。
      #   计数两个数取自原生 `fetch_project_folders` 的 SQL 别名 `projects_count` /
      #   `folders_count`（原生表格的 `folder_info` 就是读它们），**不是**这里现算的 ——
      #   现算就多一份口径，且必然与原生的「不排除归档子项」口径分叉。
      #   别名取不到（老调用方直接塞对象进来）→ nil，此时宁可不下发文案也不编一个 0。
      #
      # 行菜单：文件夹**专属集合**（编辑 / 移动 / 删除），与项目行集合互不混用
      #   （spec SCN-PROJ-LIST-7 第 6 条：不得出现访问权限 / 归档 / 评论 / 动态）。
      #   门禁逐条对照原生 `Toolbars::ProjectsService`：
      #     edit   → `can_create_project_folders?(folder.team)`   （原生 edit_action 的 else 支）
      #     move   → `can_manage_team?(folder.team)`              （原生 move_action）
      #     delete → `can_delete_project_folder?(folder)`         （原生 delete_folder_action）
      #   ⚠ delete 的谓词自带「文件夹必须为空」条件
      #     （`app/permissions/team.rb:89-93`：`projects.none? && project_folders.none?`）
      #     —— 非空文件夹删不掉，此时该项**不渲染**（原生 compact 掉，不是渲染再置灰）。
      # ------------------------------------------------------------
      def folder_row(folder)
        {
          id: folder.id.to_s,
          code: folder_code(folder),
          folder: true,
          name: folder.name.to_s,
          # 「x 个项目 | y 个文件夹」——文案形状照原生 i18n
          # `projects.index.folder.description`（en: "%{projects_count} projects | %{folders_count} folders"）。
          # ⚠ zh-CN 里**缺**这个键（实测只有 en.yml 有），所以这里带中文 default：
          #   不兜 default 的话中文界面会直接显示 "translation missing"。
          folderInfo: folder_info(folder),
          # 进入该文件夹层级（SCN-PROJ-LIST-7 第 4 条）。前端只读这个字段跳转，
          # 绝不自己拼宿主路由（铁律：路径词汇表只一套）。
          drillUrl: folder_url_for(folder),
          # 「打开」项在文件夹行里的落点就是 drillUrl（见前端 menuItemsFor）。
          detailUrl: folder_url_for(folder),
          archived: folder.respond_to?(:archived) ? !!folder.archived : false,
          starred: false,
          status: nil,
          startDate: nil,
          due: nil,
          owner: { name: '—', initial: '·', color: AVATAR_COLORS[0] },
          completed: 0,
          total: 0,
          tasksCompleted: 0,
          tasksTotal: 0,
          commentsCount: 0,
          description: nil,
          createdAt: nil,
          updatedAt: nil,
          archivedOn: date(folder.respond_to?(:archived_on) ? folder.archived_on : nil),
          folderId: folder.respond_to?(:parent_folder_id) ? folder.parent_folder_id&.to_s : nil,
          members: [],
          extra: 0,
          actions: folder_actions(folder)
        }
      end

      def folder_actions(folder)
        return NO_USER_FOLDER_ACTIONS.dup unless current_user

        {
          edit: folder_action(:edit, 'PATCH', folder_path_of(folder), folder),
          move: folder_action(:move, 'POST', move_to_project_folders_path_of, folder,
                              folders_tree_url: tree_project_folders_path_of,
                              root_key: 'root_folder'),
          # 删除是**批量**端点（原生 `project_folders#destroy` 收 `project_folder_ids`），
          # 单行删除也要包成数组 —— 原生 delete_folder 动作同样把 rows 映射成数组。
          delete: folder_action(:delete, 'POST', destroy_project_folders_path_of, folder,
                                body_key: 'project_folder_ids')
        }
      end

      def folder_action(key, method, url, folder, **extra)
        { enabled: !!folder_gate(key, folder), method: method, url: url }.merge(extra)
      end

      def folder_gate(key, folder)
        case key
        when :edit then can_create_project_folders?(folder.team)
        when :move then can_manage_team?(folder.team)
        when :delete then can_delete_project_folder?(folder)
        else false
        end
      rescue StandardError => e
        # 与 project 侧同款：判不出来就判 false —— 宁可少一项，也不给一个点下去 403 的入口。
        Rails.logger.warn("[eln_ui] folder action gate failed key=#{key} #{e.class}: #{e.message}")
        false
      end

      def folder_info(folder)
        projects_count = folder.respond_to?(:projects_count) ? folder.projects_count : nil
        folders_count = folder.respond_to?(:folders_count) ? folder.folders_count : nil
        return nil if projects_count.nil? || folders_count.nil?

        ::I18n.t('projects.index.folder.description',
                 projects_count: projects_count.to_i,
                 folders_count: folders_count.to_i,
                 default: '%{projects_count} 个项目 | %{folders_count} 个文件夹')
      rescue StandardError => e
        Rails.logger.warn("[eln_ui] folder info failed: #{e.class}: #{e.message}")
        nil
      end

      # `PrefixedIdModel#code`（`PR<id>` / `PF<id>`）。模型没混这个 concern（老库/测试替身）
      # 就**不下发**这个字段（nil）而不是现拼字符串 —— 前缀是宿主的规则，不是我们的。
      def project_code(project)
        project.respond_to?(:code) ? project.code.to_s : nil
      end

      def folder_code(folder)
        folder.respond_to?(:code) ? folder.code.to_s : nil
      end

      def folder_url_for(folder)
        return nil unless @folder_url_base

        "#{@folder_url_base}?project_folder_id=#{folder.id}"
      end

      # ------------------------------------------------------------
      # V1.32 文件夹层级导航块
      #
      # current —— 当前所在文件夹（顶层时 nil）
      # trail   —— 祖先链，**根 → 当前**（含当前），前端据此画面包屑
      # upUrl   —— 「返回上一层」的落点；顶层为 nil ⇒ 前端不渲染该入口
      #           （显式留白，不是渲染一个点了回原地的死按钮）
      #
      # ⚠ URL 一律由这里拼（`@folder_url_base` = 本页真实路径，由 controller 从
      #   `request.path` 取）—— 前端不写死 '/eln_project_list'，路由改名两侧不会脱钩。
      # ------------------------------------------------------------
      def folder_nav_block
        return { current: nil, trail: [], upUrl: nil } if @current_folder.blank? || @folder_url_base.blank?

        trail = @folder_trail.filter_map { |f| folder_crumb(f) }
        parent_id = @current_folder.respond_to?(:parent_folder_id) ? @current_folder.parent_folder_id : nil

        {
          current: folder_crumb(@current_folder),
          trail: trail,
          upUrl: parent_id.present? ? folder_url_for_id(parent_id) : @folder_url_base
        }
      end

      def folder_crumb(folder)
        return nil if folder.blank?

        {
          id: folder.id.to_s,
          name: folder.name.to_s,
          code: folder_code(folder),
          url: folder_url_for(folder)
        }
      end

      def folder_url_for_id(id)
        "#{@folder_url_base}?project_folder_id=#{id}"
      end

      # ------------------------------------------------------------
      # 行菜单行动（原生口径对齐 Toolbars::ProjectsService）
      #
      # | key      | 原生动作名 | 原生端点                                                  | gate                                    |
      # |----------|-----------|-----------------------------------------------------------|-----------------------------------------|
      # | edit     | edit       | PATCH  /projects/:id                                       | can_manage_project?                     |
      # | access   | access     | GET /access_permissions/projects/:id（成员 CRUD 同前缀）    | can_manage_team? || can_read_project?  |
      # | move     | move       | GET /project_folders/tree + POST /project_folders/move_to | can_manage_team?(team)                  |
      # | export   | export     | POST   /teams/:team/export_projects                        | can_export_project?                     |
      # | archive  | archive    | POST   /projects/archive_group {project_ids: [...]}        | can_archive_project?                    |
      # | comment  | comments   | GET    /comments?object_type=Project&object_id=:id          | can_read_project?                       |
      # | activity | activities | GET    /global_activities?subjects=Project:...              | can_read_project?                       |
      #
      # 🔴 没有 current_user（原型独立跑 / 无请求上下文）时**全部 enabled: false** ——
      #   宁可一个菜单项都点不动，也不能凭原型演示值假装能点（本项目铁律）。
      # ------------------------------------------------------------
      def row_actions(project)
        return NO_USER_ACTIONS.dup unless current_user

        {
          # 原生 edit_action 是 type: :emit 且**没有 path**（前端自己弹原生同款
          # NewProjectModal）。承载落点 = 原生 ProjectsController#update，
          # permit: name/archived/due_date/start_date/description/status/supervised_by_id
          # (+ project_folder_id，见 move)。写端点就复用同一个 projects#update。
          edit: action(:edit, 'PATCH', project_path_of(project), project),
          access: action(:access, 'GET', access_permissions_project_path_of(project), project),
          # 原生 move_action 的 path 是 /project_folders/move_to_modal（原生自己的弹窗），
          # 我们这里不套原生 bootstrap modal，改走**同一批原生数据端点**：
          #   目标树 = GET  /project_folders/tree        （folders_tree → [{folder, children}]）
          #   写回   = POST /project_folders/move_to     （原生 modals/move.vue 同一个）
          #
          # 🔴 2026-10-06 实测纠错：这里**不是** PATCH /projects/:id。
          #    projects_controller#project_update_params 只 permit
          #    name/archived/due_date/start_date/description/status/supervised_by_id，
          #   ** 不含 project_folder_id ** —— 走 PATCH 原生会静默吞掉字段、
          #   前端却 toast「已保存」，是个彻底的真绿假通（本轮真机验收抓出来的）。
          #   原生落点（app/javascript/vue/projects/modals/move.vue submit）：
          #     POST { destination_folder_id: folderId || 'root_folder',
          #            movables: [{ id, type: 'projects' }] }
          move: action(:move, 'POST', move_to_project_folders_path_of, project,
                       folders_tree_url: tree_project_folders_path_of,
                       root_key: 'root_folder'),
          export: action(:export, 'POST', export_projects_team_path_of(project.team), project),
          archive: action(:archive, 'POST', archive_group_projects_path_of, project,
                          body_key: 'project_ids'),
          comment: action(:comment, 'GET', comments_path_of(project), project),
          activity: action(:activity, 'GET', activity_url_for(project), project)
        }
      end

      # 权限判据 —— 逐条照抄原生 Toolbars::ProjectsService 的 gate，
      # 用的是同一批 Canaid 谓词，所以「我们菜单里出现什么」与
      # 「原生 /projects 行菜单出现什么」是一致的（同源同层，access_control D8 同原则）。
      # ⚠ 此处一律用 # 注释：Ruby 没有 /** */ 块注释，/** 会被当成正则字面量，
      #   注释里的 /projects 会提前闭合正则 → SyntaxError → 生产 eager_load 直接崩。
      def action_gate(key, project)
        case key
        when :edit then can_manage_project?(project)
        # 原生 access_action：团队管理员 or 项目可读（注意不是 can_manage_project?）
        when :access then can_manage_team?(project.team) || can_read_project?(project)
        when :move then can_manage_team?(project.team)
        when :export then can_export_project?(project)
        when :archive then can_archive_project?(project)
        # comments / activities：都是 can_read_project?（原生同款）
        when :comment, :activity then can_read_project?(project)
        else false
        end
      rescue StandardError => e
        # 判不出来（谓词未注册 / 参数不对）就**判 false** ——
        # 宁可菜单少一项，也不能给一个点下去 403 的入口。
        Rails.logger.warn("[eln_ui] row action gate failed key=#{key} #{e.class}: #{e.message}")
        false
      end

      def action(key, method, url, project, **extra)
        { enabled: !!action_gate(key, project), method: method, url: url }.merge(extra)
      end

      # ------------------------------------------------------------------
      # 原生路径 helper（只在 payload 里取一次，前端永不拼宿主义定路由）
      # ------------------------------------------------------------------
      def project_path_of(project)
        routes.project_path(project)
      end

      def access_permissions_project_path_of(project)
        routes.access_permissions_project_path(project.id)
      end

      def archive_group_projects_path_of
        routes.archive_group_projects_path
      end

      def export_projects_team_path_of(team)
        routes.export_projects_team_path(team)
      end

      def tree_project_folders_path_of
        routes.tree_project_folders_path
      end

      def move_to_project_folders_path_of
        routes.move_to_project_folders_path
      end

      # 文件夹 PATCH 落点（原生 project_folders#update，强参数 project_folder[name|parent_folder_id|archived]）。
      def folder_path_of(folder)
        routes.project_folder_path(folder)
      end

      # 文件夹删除是**批量** POST（原生 project_folders#destroy，收 project_folder_ids）。
      def destroy_project_folders_path_of
        routes.destroy_project_folders_path
      end

      # 「可指派成员」下拉的真源：原生 projects#users_filter（GET /projects/users_filter）。
      #
      # 🔴🔴 曾经用过 /access_permissions/projects/new，那是**死的**（2026-10-06 实测 404，
      #   下拉恒为 0 个候选、报错被吞成空数组）：
      #   · 路由顺序是对的（new 在 :id 之前声明，不会被当成 id=new 吃掉）；
      #   · 但 AccessPermissions::ProjectsController#set_model 是
      #     `current_team.projects.find_by(id: params[:id])`，而 #new 的 params[:id] 恒为字符串 "new"
      #     → find_by(id: "new") = nil → render_404。原生自己也没人调这个端点。
      #   · 加载名单的逻辑（current_team.users 排除已指派）只存在于那个坏掉的方法里。
      # 所以这里改用原生**在服役**的团队用户端点 /projects/users_filter
      # （原生 my_modules 索引的指派人筛选也用它），返回
      # `{data:[[user_id, user_name, {avatar_url}]]}`；「排除已指派」这一步由前端
      # 拿 #show 的成员列表做（与原生同一条谓词，只是从服务端挪到前端算）。
      def assignable_users_path_of
        routes.users_filter_projects_path
      end

      def comments_path_of(project)
        routes.comments_path(object_type: 'Project', object_id: project.id)
      end

      # 原生 projects.project_folder_id（可空）。没有这列（原型/老库）就 nil = 显式留白。
      def project_folder_id_of(project)
        return nil unless project.respond_to?(:project_folder_id)

        id = project.project_folder_id
        id ? id.to_s : nil
      end

      def routes
        Rails.application.routes.url_helpers
      end

      # 原生 activities_action 的 path：/global_activities?subjects=Project%3A<id>
      def activity_url_for(project)
        return nil unless project.respond_to?(:name)

        "/global_activities?#{Activity.url_search_query(subjects: { Project: [project] })}"
      rescue StandardError => e
        Rails.logger.warn("[eln_ui] activity url failed: #{e.class}: #{e.message}")
        nil
      end

      # Canaid 的 can_*? 全靠 method_missing 解析，找不到 current_user 就直接
      # NoMethodError；这里显式补一个，让 payload 在无 controller 上下文时也能判。
      def current_user
        @current_user
      end

      # ------------------------------------------------------------
      # 计数索引：一次 SQL 把整页项目的实验/任务/评论数算完，避免 N+1。
      # 口径与原生 fetch_projects 一致（见 project_row 注释）。
      # 拿不到（表/列缺失）就退回 0 —— 宁可显示 0 也不伪造。
      # ------------------------------------------------------------
      def stats_index
        @stats_index ||= build_stats_index
      end

      def build_stats_index
        ids = @projects.map(&:id).compact
        return {} if ids.empty?

        active_experiments = Experiment.where(project_id: ids, archived: false)
        active_tasks = MyModule.where(archived: false)
                               .joins(:experiment)
                               .where(experiments: { project_id: ids, archived: false })

        experiments = active_experiments.group(:project_id).count
        completed_experiments = active_experiments.where.not(done_at: nil).group(:project_id).count
        tasks = active_tasks.group('experiments.project_id').count
        completed_tasks =
          final_status_id.present? ? active_tasks.where(my_module_status_id: final_status_id)
                                                 .group('experiments.project_id').count
                                   : {}
        # ⚠ ProjectComment 的外键是 associated_id（belongs_to :project, foreign_key: :associated_id），
        #   comments 表**没有** project_id 列 —— 写 where(project_id:) 会 PG::UndefinedColumn，
        #   rescue 只能吞 Ruby 异常、吞不掉已被 PG 标记 abort 的事务：生产端静默退化成 0，
        #   测试端（transactional fixtures）直接把后续 17 例全炸成 InFailedSqlTransaction。
        #   所以这里走原生同款 joins(:project)。
        comments = ProjectComment.joins(:project).where(projects: { id: ids }).group('projects.id').count

        ids.each_with_object({}) do |id, acc|
          acc[id] = {
            experiments: experiments[id].to_i,
            completed_experiments: completed_experiments[id].to_i,
            tasks: tasks[id].to_i,
            completed_tasks: completed_tasks[id].to_i,
            comments: comments[id].to_i
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[eln_ui] project stats failed: #{e.class}: #{e.message}")
        {}
      end

      def stats_for(project_id)
        stats_index[project_id] || { experiments: 0, completed_experiments: 0,
                                     tasks: 0, completed_tasks: 0, comments: 0 }
      end

      def final_status_id
        return @final_status_id if defined?(@final_status_id)

        @final_status_id =
          begin
            MyModuleStatusFlow.first&.final_status&.id
          rescue StandardError
            nil
          end
      end

      # 描述列：原生存的是富文本（ActionText/HTML），表格里只显示纯文本摘要。
      # ⚠ 用 ActionView::Base.full_sanitizer（rails-html-sanitizer 1.7.1 下
      #   Rails::Html::Sanitizer.full_sanitizer 返回的是类不是实例，会 500）。
      def description_of(project)
        raw = project.respond_to?(:description) ? project.description.to_s : ''
        return nil if raw.blank?

        text = ActionView::Base.full_sanitizer.sanitize(raw).to_s.squish
        return nil if text.blank?

        text.length > 120 ? "#{text[0, 120]}…" : text
      rescue StandardError
        nil
      end

      # ------------------------------------------------------------
      # 状态：原生由 started_at / done_at / archived 推导，不是枚举列
      # ------------------------------------------------------------
      def status_of(project)
        return 'done' if project.respond_to?(:done_at) && project.done_at.present?
        return 'notstarted' if project.respond_to?(:started_at) && project.started_at.blank?

        'active'
      end

      def done_exp?(exp)
        exp.respond_to?(:done_at) ? exp.done_at.present? : false
      end

      # ------------------------------------------------------------
      # 负责人：原生是 projects.supervised_by_id（belongs_to User，可空）
      # ⚠ OPEN-1（未裁决）：原型把「项目负责人」映射到 Owner 角色包，addon 这边用的是
      #   supervised_by + 项目内 UserRole。两口径哪天统一，这里和 ProjectDetailPayload
      #   #owner_text 是同一处要跟着改的地方（两处都改，别只改一个）。
      # ------------------------------------------------------------
      def owner_of(project, index)
        user = supervised_user(project) || creator_user(project)
        return { name: '—', initial: '·', color: AVATAR_COLORS[index % AVATAR_COLORS.length] } if user.blank?

        avatar_of(user)
      end

      def supervised_user(project)
        return nil unless project.respond_to?(:supervised_by_id)
        return nil if project.supervised_by_id.blank?

        User.find_by(id: project.supervised_by_id)
      end

      def creator_user(project)
        return nil unless project.respond_to?(:created_by_id)

        User.find_by(id: project.created_by_id)
      end

      # ------------------------------------------------------------
      # 成员：项目上的 UserAssignment（个人）+ UserGroupAssignment（用户组）。
      #
      # ⚠ V1.32 修：之前只读了 user_assignments，**漏读 user_group_assignments** ——
      #   这正是 dy 经 epp小组 组授予合法看到 PR36、却在本列"解释不了"的根：列里只显示
      #   个人 Owner，组授予不显。原生 prepare_assigned_users 同时拼两路，这里对齐
      #   （闭合 SCN-PROJ-LIST-3：组员看所属项目，组授予必须可见）：
      #     · 个人 → { kind: 'user', name, initial, color }（沿用 avatar_of）
      #     · 组   → { kind: 'group', name: "组名 - 角色显示名", initial: '组', color }
      #   组授予限定当前团队，与原生 `where(team: current_user.current_team)` 同口径。
      #   形状统一为哈希（不再返回 [ua, user] 二元组），project_row 直接用、不再二次 map。
      # ------------------------------------------------------------
      # ⚠ 次序照原生：返回 **组在前、人在后**（原生 prepare_assigned_users 就是
      #   `user_groups + users`）。别改成「人先组后」—— 列里只渲染前 3 个 + 一个 "+N"，
      #   成员一多，组排在后面就会被挤进 "+N" 里看不见，等于本次修复白做。
      def members_for(project)
        return [] unless project.respond_to?(:user_assignments)

        # 用户组授予（当前团队下）—— 这就是 dy 经 epp小组 看到 PR36 的可见性来源
        group_entries = []
        team = current_team_of
        if team && project.respond_to?(:user_group_assignments)
          project.user_group_assignments
                 .where(team: team)
                 .to_a
                 .each do |uga|
                   next if uga.user_group.blank?
                   group_entries << {
                     kind: 'group',
                     name: uga.respond_to?(:user_group_name_with_role) ? uga.user_group_name_with_role : uga.user_group.name.to_s,
                     initial: '组',
                     color: GROUP_AVATAR_COLOR
                   }
                 end
        end

        # 个人授予（Project 级 UserAssignment）
        user_entries = []
        project.user_assignments
               .where(assignable_type: 'Project')
               .order(:created_at)
               .to_a
               .each do |ua|
                 user = ua.user
                 next if user.blank?
                 user_entries << avatar_of(user).merge(kind: 'user')
               end

        group_entries + user_entries
      end

      # 当前团队：payload 只收了 current_user，没有 current_team，按 controller 同款
      # 推导（ApplicationController：current_user.teams.find_by(id: current_team_id)）。
      # 取不到团队时返回 nil —— 组授予那段会整体跳过（个人授予不受影响）。
      def current_team_of
        return nil unless @current_user.respond_to?(:current_team_id) && @current_user.respond_to?(:teams)
        return nil if @current_user.current_team_id.blank?

        @current_user.teams.find_by(id: @current_user.current_team_id)
      end

      def avatar_of(user)
        name = user.full_name.presence || user.email.to_s
        {
          name: name,
          initial: initials_of(user, name),
          color: AVATAR_COLORS[(user.id || 0) % AVATAR_COLORS.length]
        }
      end

      def initials_of(user, name)
        # User#initials 是原生方法（"张负责人" → "张"）；拿不到就取首字，不至于渲染成空白。
        initial = user.respond_to?(:initials) ? user.initials.presence : nil
        initial.presence || name.to_s.first.to_s || '·'
      end

      def date(value)
        return nil if value.blank?

        value.respond_to?(:strftime) ? value.strftime(DATE_FMT) : value.to_s
      end

      def datetime(value)
        return nil if value.blank?

        value.respond_to?(:strftime) ? value.strftime(DATETIME_FMT) : value.to_s
      end

      # ------------------------------------------------------------
      # V1.27：深链筛选条件归一化（闭合 OPEN-WB-DRILL-8）
      #
      # 把 controller 传来的 `params[:filters]`（普通 Hash、**字符串键**）归一化成与前端
      # `ui.filters` **完全同形**的对象，供 entry 直接 `Object.assign(ui.filters, ...)`。
      #
      # ⚠ 类型必须归一（本改动最容易静默失败的点）：
      #   深链 URL 里 `filters[members][]=35` 解码后是**字符串** "35"，而 FilterPanel 的
      #   `<option :value="m.id">`（真机 members 选项 id 是**数字**）—— `v-model` 多选按
      #   **严格相等**匹配 option，字符串 vs 数字会匹配不上 → 现象是「回填了但多选框不显示」，
      #   属于最难查的那类静默失败。所以这里把纯数字串转成 Integer。
      #   （headOfProject 的 id 同理。）
      # ⚠ 键名要与 ui.filters 一一对齐：UI 里是 `headOfProject`（驼峰），原生参数是
      #   `head_of_project`（下划线）—— 这里做最后一次映射，别把两种词汇表漏到前端。
      # ------------------------------------------------------------
      def normalized_initial_filters
        raw = @initial_filters.to_h.stringify_keys
        return {} if raw.blank?

        out = {}
        out['query'] = raw['query'].to_s if raw['query'].present?

        members = normalize_id_array(raw['members'])
        out['members'] = members if members.any?

        out['headOfProject'] = normalize_id(raw['head_of_project']) if raw['head_of_project'].present?

        INITIAL_DATE_FILTER_KEYS.each do |key|
          out[key] = raw[key].to_s if raw[key].present?
        end

        statuses = Array(raw['statuses']).map(&:to_s).reject(&:blank?)
        out['statuses'] = statuses if statuses.any?

        out
      end

      # 纯数字串 → Integer（对齐真机 option id 的类型）；非数字原样保留字符串。
      def normalize_id(value)
        str = value.to_s
        str.match?(/\A\d+\z/) ? str.to_i : str
      end

      # 数组逐项归一（members 多选值）；空白项丢弃。
      def normalize_id_array(value)
        Array(value).filter_map do |item|
          str = item.to_s
          next nil if str.blank?

          str.match?(/\A\d+\z/) ? str.to_i : str
        end
      end
    end
  end
end
