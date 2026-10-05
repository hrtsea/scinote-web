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

      # 无用户上下文时的行行动（原型独立跑 / 测试里没传 current_user）：
      # 每一项都是 enabled: false —— 菜单照渲染但点不动，绝不按演示值假装可用。
      NO_USER_ACTIONS = ACTION_KEYS.each_with_object({}) do |k, h|
        h[k] = { enabled: false, method: 'GET', url: nil }
      end.freeze

      # 🔴 Canaid 的 can_*? 全部走 method_missing（见 canaid/helpers/permissions_helper.rb），
      #    挂在 Service 上时没有 controller 的 current_user，必须自己定义（见 #current_user）。
      include Canaid::Helpers::PermissionsHelper

      # 原型头像配色（avatarPalette 的 5 个 key），按下标轮转，保证同一列表里稳定。
      AVATAR_COLORS = %w[blue green orange cyan purple].freeze

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
                 option_errors: [], initial_filters: {})
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
              initial_filters: initial_filters).call
        end
      end

      def initialize(projects, can_create_project: false, can_create_folder: false,
                     folders: [], members: [], head_of_projects: [], statuses: [],
                     default_roles: [], create_urls: {}, list_url: nil, view_mode: 'active',
                     detail_url_base: nil, current_user: nil, workbench_url: nil,
                     option_errors: [], initial_filters: {})
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
          projects: projects_block
        }
      end

      private

      def projects_block
        @projects.each_with_index.map { |p, i| project_row(p, i) }
      end

      def project_row(project, index)
        stats = stats_for(project.id)
        members = members_for(project)

        {
          # 原型 id 是业务编号（PR1025240）；原生没这列 → 用主键，不编业务编号。
          id: project.id.to_s,
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
          members: members.map { |_ua, u| avatar_of(u) }.first(3),
          extra: [members.size - 3, 0].max,
          # 行菜单 7 项的真源（gate + 原生端点，前端照此渲染/分发）
          actions: row_actions(project)
        }
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
      # 成员：项目上的 UserAssignment（不含负责人本身，负责人另有 owner 列）
      # ------------------------------------------------------------
      def members_for(project)
        return [] unless project.respond_to?(:user_assignments)

        project.user_assignments
               .where(assignable_type: 'Project')
               .order(:created_at)
               .to_a
               .map { |ua| [ua, ua.user] }
               .reject { |_ua, user| user.blank? }
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
