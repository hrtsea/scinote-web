# frozen_string_literal: true

# ELN UI —— 项目列表页（按 Vue3 原型重建的第二页）
#
# 与详情页 controller 同一套样板：侧栏/顶栏/布局容器走 SciNote 原生，
# 内容区只留一个挂载点 #eln-project-list，交给 ELN系统-Vue3/src/entries/project_list.js
# 的 bundle 接管；数据由 ProjectListPayload 出，以 JSON 块注入，没有第二个数据源。
#
# 与详情页不同的两件事：
#   1. 列表页是**一层往平看**，所以权限判断落在「这个项目我能不能读」而不是「能不能看某个项目页」；
#   2. 要额外决定「新建项目」按钮显不显（PRD §7.4 SCN-PROJ-LIST-4：仅单位管理员可见可用）。

module Scinote
  module ElnUi
    class ProjectListController < ApplicationController
      # 🔴 2026-10-06：@view_mode 必须在取数**之前**定下来。
      #   它原本只在 payload 的实参里赋值（`view_mode: @view_mode ||= ...`），而
      #   `filtered_projects` 是实参列表里的**第一项** —— Ruby 自左向右求值，
      #   scoped_projects 跑的时候 @view_mode 还是 nil，下面那层过滤就成了摆设。
      before_action :set_view_mode

      # 两条出口：
      #   html —— 老样子，payload 内联成 JSON 注入挂载点（首屏零额外请求）；
      #   json —— 工具栏那几个按钮「改完条件/建完项目」之后只刷新**数据**，不整页重载。
      #
      # 工具栏到底要刷新什么（原生 toolbar.vue 那 7 个控件）：
      #   视图/状态切换 → view_mode（原生 projects#index 同名参数）；
      #   搜索/筛选     → search + filters[...]（键名与原生 Lists::ProjectsService 一一对齐）；
      #   列显隐        → 纯前端（不回服务端，列本身不动）；
      #   新建项目/文件夹 → POST 原生端点后走 json 出口重拉列表。
      def index
        @can_create_project = can_create_project?
        @can_create_folder = can_create_folder?

        respond_to do |format|
          format.html { @payload_json = JSON.generate(payload).gsub('<', '\\u003c') }
          format.json { render json: payload }
        end
      end

      # V2.0 —— AG Grid 契约 JSON（供原生 shared/datatable 消费）。
      # 复用现有 ProjectListPayload 的行装配（项目∪文件夹、17 列 ELN 形状、stats/members/
      # owner/status/actions 全算好），仅把 :projects 数组包成 JSON:API 形状
      # { data:[{ id, type, attributes }], meta:{total_pages,total_count,filtered_count} }。
      # table.vue 的 formatData 会把 attributes + id + type 展开成 AG Grid 行，列定义用
      # field 命中 attributes 里的字段。后端零新增序列化逻辑，ELN 行集合仍是唯一真源。
      def grid
        full = payload
        rows = full[:projects].map do |h|
          { id: h[:id], type: h[:folder] ? 'project_folder' : 'project', attributes: h }
        end
        meta = {
          total_pages: full[:pagination][:totalPages],
          total_count: full[:pagination][:totalEntries],
          filtered_count: full[:totalEntries] || full[:pagination][:totalEntries]
        }
        render json: { data: rows, meta: meta }
      end

      # ADR-0038-C 批量操作条的动作来源端点（宿主 shared/datatable 的 actionsUrl）。
      #
      # 多选后宿主内建的 <ActionToolbar>（shared/datatable/action_toolbar.vue）会 POST 到这里，
      # 拿到「在当前选中集合上可用的公共动作」并把它们渲染成按钮；点击再 emit 回父组件。
      # 动作与逐项权限判定**全部复用宿主 `Toolbars::ProjectsService`**（can_archive_project? /
      # can_delete_project_folder? / can_manage_team? …），不在这里重写一份动作/权限表 ——
      # 与原生 /projects 的批量条同一真源。
      #
      # 与原生端点 projects#actions_toolbar 的两点差异（有意）：
      #   ① 原生按 type=='projects'/'project_folders'（**复数**）分流，而 ELN 行 type 是单数
      #      'project'/'project_folder'（grid 端点自定义）⇒ 这里按单数映射，前端不必改。
      #   ② 只暴露**已接线的批量动作**（归档/恢复/删除文件夹/移动）；宿主 Service 还会返回
      #      edit/access/comments/activities/export 等，其中单读类动作由行 kebab 菜单承担，
      #      这里不重复暴露以免渲染出「点了没反应」的死按钮。
      def actions
        items = JSON.parse(params[:items].presence || '[]')
        folder_ids = items.select { |i| i['type'] == 'project_folder' }.pluck('id')
        project_ids = items.select { |i| i['type'] == 'project' }.pluck('id')

        # ⚠ 项目集合走 scoped_projects（已含 current_team + readable_by_user 两条口径），
        #   不直接 Project.where(id:) —— 后者会跨团队/跨权限拿到别人的项目。
        projects = scoped_projects.where(id: project_ids)
        folders = current_team.project_folders.where(id: folder_ids)

        allowed = %w[archive restore delete_folders move]
        all_actions = ::Toolbars::ProjectsService.new(projects, folders, current_user).actions
        render json: { actions: all_actions.select { |a| allowed.include?(a[:name].to_s) } }
      rescue JSON::ParserError
        head :bad_request
      end

      private

      # ------------------------------------------------------------
      # 过滤 + 排序：**原样复用原生 Lists::ProjectsService**，不造第二套口径。
      #
      # 为什么敢调它的私有方法：这里只需要「按条件收敛/排序我这一份 scoped_projects」，
      # 而 service 的 call() 会把 projects + folders 混在一起再分页，形状对不上我们的
      # payload（列表行要区分项目/文件夹）；filter_project_records 是纯过滤、
      # sort_records 是纯排序（吃 `order[column]` + `order[dir]`，非 asc 一律 DESC，
      # 与原生 projects 页同一条 case 分支：name/code/status/due_date/supervised_by/
      # users/completed_experiments/...），条件键与原生完全同源 ——
      # 谁改了原生的过滤/排序语义，我们这边自动跟着变，不会出现「原生能排、这里排不动」。
      #
      # ⚠ sort_records 操作的是 service 的 @records 实例变量（call() 里先赋值再排序），
      #   我们绕过 call()，所以要先把过滤结果塞回 @records 再调它 —— 三行胶水，
      #   比复制那份 30 个分支的 case 划算得多。
      # ------------------------------------------------------------
      def filtered_projects
        @filtered_projects ||= begin
          scope = scoped_projects
          service = Lists::ProjectsService.new(current_team, scope, nil, params, user: current_user)
          records = service.send(:filter_project_records, scope)
          service.instance_variable_set(:@records, records)
          service.send(:sort_records)
          service.instance_variable_get(:@records)
        end
      end

      # ------------------------------------------------------------
      # V1.32 行集合（票 #84）—— 项目行 ∪ 文件夹行
      #
      # 🔴 行集合的**唯一真源**是 `Scinote::ElnUi::ProjectListRows`（本 controller 只做
      #   委托，不在这里写第二份「有筛选就只出项目」的判断）。它内部逐字复刻原生
      #   `Lists::ProjectsService#call` L22-31 的三分支，并有对拍用例守着。
      #
      # ⚠ 与 `filtered_projects` 的关系：后者是**只管项目**的那一条路，仍被工作台
      #   不变式的对拍用例（`SCN-DASH-8`：卡片数字 ≡ 列表条数）与其余老调用方使用。
      #   两条都保留不是「两份定义」—— 行集合那条是它的**超集**，且项目行的过滤/排序
      #   仍然全部走同一批原生私有方法（`filter_project_records` / `sort_records`）。
      # ------------------------------------------------------------
      def row_set
        @row_set ||= Scinote::ElnUi::ProjectListRows.call(
          team: current_team,
          user: current_user,
          view_mode: @view_mode,
          params: params,
          scope: scoped_projects,
          current_folder: current_folder
        )
      end

      # 当前所在文件夹（SCN-PROJ-LIST-7 第 4 条：进入文件夹层级 / 返回上一层）。
      #
      # 参数名与原生**逐字一致**（`project_folder_id`，原生 `projects#index` 同名同义）——
      # 不自造 `folder` / `dir` 之类别名。
      # ⚠ 查找**必须限定 current_team**：`ProjectFolder.find_by(id:)` 会跨团队拿到别人的
      #   文件夹，等于用 URL 里的一个数字探测全库（本项目铁律：权限判定先问承载面）。
      # ⚠ 传了不存在的 id → nil → 退回顶层，**不报 404、不 500**：与原生
      #   `load_current_folder`（`find_by` 得 nil）同行为，且用户手改 URL 不会炸页面。
      def current_folder
        return @current_folder if defined?(@current_folder)

        id = params[:project_folder_id]
        @current_folder = id.present? ? current_team.project_folders.find_by(id: id) : nil
      end

      # ------------------------------------------------------------
      # V1.31 分页 —— 参数名与原生**逐字一致**（`page` / `per_page`）
      #
      # 原生 Lists::BaseService#paginate_records 就是
      #   `@records.page(@params[:page]).per(@params[:per_page])`（kaminari）。
      # 这里不自造 `p` / `size` / `limit` 之类别名 —— 同一件事两套词汇表是本项目的老毛病。
      #
      # ⚠ 为什么不用 Kaminari：
      #   原生的 @records 有两种形态 —— 无筛选时是 `projects + folders`（Array），
      #   sort_records 里那批 `sort_by` 也会把 relation 变成 Array；我们的
      #   row_set.rows 同样恒是 Array（并集已经 to_a 过）。
      #   Kaminari 的 page/per 开箱只对 ActiveRecord::Relation 可用（Array 必须显式
      #   `Kaminari.paginate_array` 包一层），走它就得先判形态，反而更脆。
      #   这里统一按数组切片：**形态无关、total 恒准确**，且与原生
      #   「先 filter → 再 sort → 最后 paginate」的三段次序完全一致。
      # ⚠ 但**语义上有一处与原生不同**（有意）：原生 `paginate_records` 直接读
      #   `@params[:per_page]` 原值，非法值会让 `.per(9999)` 返回全量；
      #   我们按 spec SCN-PROJ-LIST-13 归一化档位（非法回落 20、0 = 全部）。
      #   代价：每次请求把筛选后的全部行载进内存（当前量级：单团队 294 行，
      #   可忽略）。**一旦单团队项目数上到万级**，这里要换回 SQL 分页 ——
      #   届时 sort_records 那批 Ruby sort_by 也得一起下推，属独立议题。
      #
      # ⚠ `per_page` 的归一化（含「0 = 全部」「非法回落 20，绝不退化成全量」）在
      #   ProjectListPayload.normalize_per_page —— 那是档位唯一真源，这里只做委托，
      #   不在这再写一遍判定（否则档位改动会漏改一处）。
      # ------------------------------------------------------------
      def paged_rows
        rows = row_set.rows.to_a
        # ⚠ 两个 total 都是**筛选后**（= 分页前）的：totalEntries 是行集合条数（含文件夹行），
        #   projectCount 是其中的项目行条数。页头「共 N 个项目」用后者，分页信息条用前者。
        @total_entries = rows.size
        @project_count = row_set.project_count
        per = per_page_param
        return rows if per.zero? # 0 = 全部（显式请求才生效，见 normalize_per_page）

        # ⚠ 越界页码返回空数组而不是 nil：Array#slice 在 offset > size 时给 nil，
        #   不兜住的话 projects_block 会在 nil 上炸 500（用户手改 URL 就能触发）。
        rows.slice((page_param - 1) * per, per) || []
      end

      def per_page_param
        Scinote::ElnUi::ProjectListPayload.normalize_per_page(params[:per_page])
      end

      def page_param
        Scinote::ElnUi::ProjectListPayload.normalize_page(params[:page])
      end

      # ------------------------------------------------------------
      # 「新建文件夹」权限
      #
      # ⚠ **不存在** `TeamPermissions::CREATE_PROJECT_FOLDERS` 这个常量（2026-10-04 实测：
      #   NameError → 整页 500）。Canaid 里 create_project_folders 不是权限位，
      #   而是由 can_manage_team? **派生**出来的谓词（app/permissions/team.rb:25），
      #   可用的常量只有 PermissionExtends::TeamPermissions.constants 那 22 个。
      #   所以这里照原生 project_folders_controller:145 的写法用生成的 helper
      #   can_create_project_folders?(team) —— 与原生同一条判定，不自己推一遍。
      # ------------------------------------------------------------
      def can_create_folder?
        can_create_project_folders?(current_team)
      end

      # ------------------------------------------------------------
      # 筛选面板可选项（原生 list.vue 的 filters() 用 i18n 文案 + 同一批键）
      #   members         → 用户下拉（项目成员筛选的候选）
      #   headOfProjects  → 负责人下拉（projects.supervised_by_id）
      #   statuses        → 状态下拉（原生按 MyModuleStatusFlow 的终态推导）
      # 取不到就给空数组，前端渲染成「不可用」而非回落原型文案。
      # ------------------------------------------------------------
      def team_users
        return [] unless current_team.respond_to?(:users)

        current_team.users.order(:id).limit(200).map do |u|
          { id: u.id, name: u.full_name.presence || u.email.to_s }
        end
      end

      # ⚠ 筛选项取数失败不许**安静地**变成空下拉：整段兜 [] 之后页面上就是一个空的
      #   「负责人/角色/文件夹」下拉，用户只会以为「没数据」，真凶躺在 log 里。
      #   这里除了 log，再把失败项记进 @option_errors 由 payload 下发（filterOptionErrors），
      #   前端据此显式提示「部分筛选项不可用」——失败必须看得见。
      def option_failed!(key, error)
        Rails.logger.error("[eln_ui] option #{key} failed #{error.class}: #{error.message}")
        (@option_errors ||= []) << key.to_s
        nil
      end

      def head_of_project_users
        current_team.users.where(id: Project.where(team_id: current_team.id)
                                            .where.not(supervised_by_id: nil)
                                            .select(:supervised_by_id))
                     .order(:id).map { |u| { id: u.id, name: u.full_name.presence || u.email.to_s } }
      rescue StandardError => e
        option_failed!('headOfProjects', e)
        []
      end

      # ------------------------------------------------------------
      # 状态下拉：⚠ **不是** MyModuleStatus 的 id，而是原生 Lists::ProjectsService
      # 能吃进去的三个 scope 键（not_started / in_progress / done，见
      # projects_service.rb:106-116 的 scopes 哈希）。拿状态流的 id 去筛会一条都不中，
      # 页面还 200 —— 属于最难查的那类「筛了个寂寞」。
      # 文案与原生 list.vue 的 statusesList 同源（I18n key projects.index.status.*）。
      # ------------------------------------------------------------
      # 🔴 **必须写 `::I18n`**：宿主定义了 `Scinote::I18n` 这个模块，而本类在
      #   `module Scinote::ElnUi` 里 —— 裸写 `I18n` 按 Ruby 常量查找会命中
      #   `Scinote::I18n` 而不是顶层 `::I18n`，于是 NoMethodError: undefined method 't'
      #   for module Scinote::I18n（2026-10-04 实测，整段 rescue 咽掉后前端拿原型三档兜底，
      #   两层兜底叠起来看着一切正常、其实筛选用错了口径）。
      #   与 model 里 belongs_to 的 class_name 必须带 :: 是同一类命名空间遮蔽坑。
      #
      # ⚠ 这里**不要**整段 rescue 成 []：整段兜 [] 会把真凶咽掉。逐条 rescue + 打日志，
      #   失败也要留下能查的痕迹，且最多退化成英文键名。
      def project_statuses
        %w[not_started in_progress done].map do |key|
          label =
            begin
              ::I18n.t("projects.index.status.#{key}", default: key)
            rescue StandardError => e
              Rails.logger.warn("[eln_ui] project_statuses label failed key=#{key} #{e.class}: #{e.message}")
              key
            end
          { id: key, name: label.to_s }
        end
      end

      # 新建项目弹窗里的「默认用户角色」下拉 —— 原生真有这个落点：
      # projects.default_public_user_role_id（projects#create 之后由
      # create_team_assignment 读 params[:project][:default_public_user_role_id]
      # 给全队按该角色发一张 TeamAssignment）。所以角色的选项是**数据库里的真角色**，
      # 不是原型那四个字符串常量。
      def default_roles
        UserRole.predefined.order(:id).map { |r| { id: r.id, name: r.name.to_s } }
      rescue StandardError => e
        option_failed!('defaultRoles', e)
        []
      end

      # 文件夹下拉（新建项目时可归到某个文件夹下）
      def team_folders
        return [] unless current_team.respond_to?(:project_folders)

        current_team.project_folders.order(:name).map { |f| { id: f.id, name: f.name.to_s } }
      rescue StandardError => e
        option_failed!('folders', e)
        []
      end

      # ------------------------------------------------------------
      # 只列「当前团队 + 当前用户可读」的项目
      #
      # 为什么不用 addon 自己那套可见性：原生 PermissionCheckableModel 的
      # readable_by_user 已经把 user_assignments / user_group_assignments /
      # team_assignments 三条授予链都走了一遍，这里再判一遍就是第二套口径。
      # 沿用 access_control 的 D8「同源同层」—— 列表能看见什么，原生列表也该能看见什么。
      #
      # team 过滤照抄原生 projects#index（原生按 current_team 切团队），
      # 否则同一个人在多团队时会看到别团队的项目。
      # ------------------------------------------------------------
      # ⚠ template 列是**可空布尔**：生产库 159 行里 158 行是 NULL、1 行是 true。
      #   写 where(template: false) 会把这 158 行全排掉 → 列表恒空（页面 200、渲染正常、
      #   就是一条数据都没有，最难看的一类空成功）。NULL 表示「不是模板」，必须显式收进来。
      #
      # ⚠🔴 2026-10-06 补的归档过滤（真 bug，不是口径偏好）：
      #   原生的 Lists::ProjectsService 只在**文件夹分支**（filter_project_folder_records）
      #   按 view_mode 切 archived/active，项目分支（filter_project_records）**没有这一层**，
      #   真正兜底的是 call() 里的 L85-86。addon 侧绕过 call() 只调 filter_project_records，
      #   于是这一层就整个漏掉了 —— 实测后果：归档 #40 之后本行还留在「活动」列表里，
      #   而原生 /projects 的同名视图会把它挪到归档视图。
      #   这里照原生那两行对齐：archived 视图看归档、其它（含默认 active）看活动。
      #
      # 🔴 V1.27：上面这三条口径（template 可空布尔 / 归档过滤 / distinct）**已搬到唯一真源**
      #   `Scinote::ElnUi::ProjectListScope#for_listing`，本方法只做委托 —— 因为工作台
      #   「参与项目」卡片要保证 **卡片数字 ≡ 点进去列表页筛出来的条数**，两侧必须走同一段
      #   可变代码，不能再各写一遍 WHERE（本项目已两次因「同一件事两份定义」出事）。
      #   ⚠ 历史注释故意保留在此 + 新类里各一份：新类里是"为什么这样写"，这里是"调用方为什么
      #     相信它"。谁要改这三条口径，去 ProjectListScope 改，**别在这里重写**。
      def scoped_projects
        ::Scinote::ElnUi::ProjectListScope
          .for_listing(team: current_team, user: current_user, view_mode: @view_mode)
          # 列表页「访问权限」列要读两路授予（个人 UA + 用户组 UGA），预加载消 N+1。
          # 仅列表页需要（工作台卡片不渲染成员列），所以加在这条列表专用链上，
          # 不污染工作台共用的 ProjectListScope 单一真源。
          .preload(user_assignments: :user, user_group_assignments: %i[user_group user_role])
          .order(name: :asc)
      end

      # view_mode 与原生 projects#index 同名同义：active（默认）/ archived。
      # 与原生完全一致（默认 active，且不认其它值时也当 active，不落到「全量」）。
      def set_view_mode
        @view_mode ||= params[:view_mode].presence || 'active'
      end

      def payload
        # 🔴 V1.31：**必须先取数**，再进实参列表。
        #   分页后 `@total_entries` / `@project_count` 是 `paged_rows` 的副作用，而 Ruby
        #   的实参是自左向右求值 —— 如果照原样把 paged_rows 写在第一个位置、
        #   `total_entries: @total_entries` 写在后面，看着能跑；但只要哪天有人
        #   调整实参顺序（或把 total_entries 提到前面），拿到的就是上一轮的旧值
        #   或 nil。本文件顶部 `set_view_mode` 那条注释记的就是同一个坑的第一次翻车
        #   （@view_mode 在实参里赋值 + filtered_projects 是第一项 → 过滤成了摆设）。
        #   所以在方法体里显式先算，不依赖实参顺序的副作用。
        rows = paged_rows

        Scinote::ElnUi::ProjectListPayload.call(
          rows,
          # V1.31 分页三件套：页码 / 档位 / **筛选后**总条数（分页前）。
          page: page_param,
          per_page: per_page_param,
          total_entries: @total_entries,
          # V1.32：纯项目行数（页头「共 N 个项目」用它，不用 totalEntries ——
          # 后者含文件夹行，用错会把文件夹算成项目，且会破坏 SCN-DASH-8 的不变式对拍）。
          project_count: @project_count,
          # V1.32 文件夹层级（当前文件夹 / 祖先链 / 下钻基址）。
          # ⚠ `folder_url_base` 用 `request.path` 而不是字面量 '/eln_project_list'：
          #   本页 html 出口的路径就是它自己，路由改名时两侧不会脱钩（与 json_self_path 同款理由）。
          current_folder: current_folder,
          folder_trail: row_set.trail,
          folder_url_base: page_self_path,
          # V1.33 列状态持久化端点基址（GET/PUT /user_settings/:key，通用 per-user KV）。
          # 与 workbench_url 同款铁律：URL 由服务端下发，前端不写死宿主路由。
          # ⚠ 两个坑（2026-10-07 实测）：
          #   ① addon 是 engine，宿主 helper 必须 url_helpers 全限定，裸调 NameError → 整页 500；
          #   ② 该 resource 只开了 show/update（member），**没有 collection 路由**
          #      ⇒ user_settings_path 这个 helper 压根不存在，只有 user_setting_path(key)。
          #      用占位 key 生成再剥掉尾巴，得到基址 '/user_settings'。
          user_settings_url: Rails.application.routes.url_helpers
                               .user_setting_path('--KEY--').chomp('/--KEY--'),
          can_create_project: @can_create_project,
          can_create_folder: @can_create_folder,
          folders: @folders ||= team_folders,
          members: @members ||= team_users,
          head_of_projects: @hop ||= head_of_project_users,
          statuses: @statuses ||= project_statuses,
          default_roles: @default_roles ||= default_roles,
          option_errors: @option_errors ||= [],
          create_urls: @create_urls ||= create_urls,
          # ⚠ 别用 eln_project_list_path(format: :json)：这个 controller 上下文里它抛
          #   ActionController::UrlGenerationError（No route matches ... format: :json），
          #   而**同一句在 rails runner 里是正常的**（2026-10-04 实测对比过）——
          #   差异来自 controller 的 _recall（当前请求参数）参与 url_for。
          #   直接用当前请求路径拼 .json：本页 html/json 就是同一条路由的两种格式，
          #   request.path 恒等于它自己，路由改名也不会脱钩。
          list_url: @list_url ||= json_self_path,
          view_mode: @view_mode ||= params[:view_mode].presence || 'active',
          # V1.27（闭合 OPEN-WB-DRILL-8）：把本次请求的筛选条件归一化后随 payload 下发，
          # 前端 entry 在挂载时回填 ui.filters。不回填有两层后果：
          #   ① 打开筛选面板看不到已生效条件（深链 ?filters[members][]=35 貌似"没生效"）；
          #   ② 任何工具栏交互都会走 refreshList()→buildListQuery()，只用**空的** ui.filters
          #      重拼 query → 深链筛选被静默丢弃（列表突然变多，页面无任何提示）。
          # ⚠ 传**已转成普通 Hash** 的值（不用 ActionController::Parameters）：service 不收
          #   Parameters（铁律）；且 Parameters 直接进 JSON 会带 permitted 语义。
          initial_filters: initial_filter_hash,
          # 下钻基址：前端拿它拼每行的 detailUrl。走同一套 _recall坑已知的
          # url_for 在本controller 里会炸，所以这里也用字面基址拼接，
          # 路由段与 config/routes.rb 的 'projects/:project_id/eln_project_detail' 一致。
          detail_url_base: @detail_url_base ||= '/projects',
          # 工作台入口（OPEN-WB-7）：宿主左菜单没有 /eln_workbench，这个字面基址是
          # 「从项目列表回/去工作台」的唯一正式入口。与 detail_url_base 同款 ——
          # 本 controller 里 url_for 会因 _recall 抛 UrlGenerationError，别改成路由 helper。
          workbench_url: @workbench_url ||= '/eln_workbench',
          # 行菜单 7 项（编辑/访问权限/移动/导出/归档/评论/动态）的权限与端点同源判定：
          # 传下去后 payload 用同一批 Canaid 谓词（can_manage_project? / can_manage_team?
          # / can_archive_project? / can_export_project? / can_read_project?），
          # 与原生 /projects 行菜单逐项对齐。不传 = 全部 enabled:false（显式留白）。
          current_user: current_user
        )
      end

      # json 出口：/eln_project_list → /eln_project_list.json（幂等，重复调用不会追加）
      def json_self_path
        "#{page_self_path}.json"
      end

      # 本页 html 出口的路径（去掉可能存在的 .json 后缀）。
      # 用途：a) json 出口自拼；b) 文件夹下钻链接（`?project_folder_id=N`）的基址。
      # ⚠ 与 json_self_path 同款理由：本 controller 里 `url_for` 会踩 _recall 抛
      #   ActionController::UrlGenerationError，所以一律用 request.path 现取，不写死字面量。
      #
      # ⚠🔴 `/grid` 必须一并剥掉（2026-10-08 实测 bug）：
      #   `grid` 动作是本页的**数据端点**而非页面本身，它的 request.path 是
      #   `/eln_project_list/grid`。不剥的话 `folder_url_base` 会变成
      #   `/eln_project_list/grid`，`folder_url_for` 拼出的下钻链接就是
      #   `/eln_project_list/grid?project_folder_id=4` ——
      #   点文件夹名称会跳到**裸 JSON 端点**（页面渲染一屏 JSON），而不是下钻进文件夹。
      #   该 bug 在「名称列不可点」时无人可见；名称列接了链接之后立即暴露。
      #   两个调用方现在都拿到正确的列表页路径：index → /eln_project_list、
      #   grid  → /eln_project_list。
      def page_self_path
        request.path.to_s.sub(/\.json\z/, '').sub(%r{/grid\z}, '')
      end

      # 本次请求的筛选条件（普通 Hash）—— 用于随 payload 下发 initialFilters，
      # 让前端深链回填 ui.filters（V1.27 / OPEN-WB-DRILL-8）。
      # ⚠ `params[:filters]` 是 ActionController::Parameters：这里转成普通 Hash 再交给
      #   ProjectListPayload（service 不收 Parameters），键保持**字符串**（to_unsafe_h 的原样）。
      def initial_filter_hash
        raw = params[:filters]
        return {} if raw.blank?

        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      end

      # ------------------------------------------------------------
      # 原生端点：前端「新建项目 / 新建文件夹」直接 POST 到这里（CSRF 由视图注入）。
      # 为什么要从服务端出，而不是前端写死 '/projects'：宿主路由前缀哪天变了，
      # 前端 bundle（原型独立跑的那份）不该跟着变，一份常量两边共用最稳。
      # ------------------------------------------------------------
      def create_urls
        {
          project: '/projects',
          folder: '/project_folders'
        }
      end

      # ------------------------------------------------------------
      # 「新建项目」权限（SCN-PROJ-LIST-4）
      #
      # ⚠ 不写 can_create_projects?(current_user, current_team)：这个版本里 Canaid 把
      #   create_projects 注册在 **Team** 上（app/permissions/team.rb:29-33），
      #   实际判定是 team.permission_granted?(user, TeamPermissions::PROJECTS_CREATE)。
      #   那条 can_create_projects? 是 helper/其它入口的封装，User 实例上 respond_to? 为 false
      #   （2026-10-04 实测探针），直接调在 addon controller 里不可靠。
      #   这里用判定本体，语义与原生完全一致，且不受 Canaid 生成规则变动影响。
      # ------------------------------------------------------------
      def can_create_project?
        current_team.permission_granted?(current_user, TeamPermissions::PROJECTS_CREATE)
      end
    end
  end
end
