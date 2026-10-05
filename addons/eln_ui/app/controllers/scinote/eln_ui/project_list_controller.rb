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
        scope = scoped_projects
        service = Lists::ProjectsService.new(current_team, scope, nil, params, user: current_user)
        records = service.send(:filter_project_records, scope)
        service.instance_variable_set(:@records, records)
        service.send(:sort_records)
        service.instance_variable_get(:@records)
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

      def head_of_project_users
        current_team.users.where(id: Project.where(team_id: current_team.id)
                                            .where.not(supervised_by_id: nil)
                                            .select(:supervised_by_id))
                     .order(:id).map { |u| { id: u.id, name: u.full_name.presence || u.email.to_s } }
      rescue StandardError
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
      rescue StandardError
        []
      end

      # 文件夹下拉（新建项目时可归到某个文件夹下）
      def team_folders
        return [] unless current_team.respond_to?(:project_folders)

        current_team.project_folders.order(:name).map { |f| { id: f.id, name: f.name.to_s } }
      rescue StandardError
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
      def scoped_projects
        scope = Project.where(team_id: current_team.id, template: [false, nil])
                       .distinct
                       .readable_by_user(current_user)
        scope = if @view_mode == 'archived'
                  scope.archived
                else
                  scope.active
                end
        scope.order(name: :asc)
      end

      # view_mode 与原生 projects#index 同名同义：active（默认）/ archived。
      # 与原生完全一致（默认 active，且不认其它值时也当 active，不落到「全量」）。
      def set_view_mode
        @view_mode ||= params[:view_mode].presence || 'active'
      end

      def payload
        Scinote::ElnUi::ProjectListPayload.call(
          filtered_projects,
          can_create_project: @can_create_project,
          can_create_folder: @can_create_folder,
          folders: @folders ||= team_folders,
          members: @members ||= team_users,
          head_of_projects: @hop ||= head_of_project_users,
          statuses: @statuses ||= project_statuses,
          default_roles: @default_roles ||= default_roles,
          create_urls: @create_urls ||= create_urls,
          # ⚠ 别用 eln_project_list_path(format: :json)：这个 controller 上下文里它抛
          #   ActionController::UrlGenerationError（No route matches ... format: :json），
          #   而**同一句在 rails runner 里是正常的**（2026-10-04 实测对比过）——
          #   差异来自 controller 的 _recall（当前请求参数）参与 url_for。
          #   直接用当前请求路径拼 .json：本页 html/json 就是同一条路由的两种格式，
          #   request.path 恒等于它自己，路由改名也不会脱钩。
          list_url: @list_url ||= json_self_path,
          view_mode: @view_mode ||= params[:view_mode].presence || 'active',
          # 下钻基址：前端拿它拼每行的 detailUrl。走同一套 _recall坑已知的
          # url_for 在本controller 里会炸，所以这里也用字面基址拼接，
          # 路由段与 config/routes.rb 的 'projects/:project_id/eln_project_detail' 一致。
          detail_url_base: @detail_url_base ||= '/projects',
          # 行菜单 7 项（编辑/访问权限/移动/导出/归档/评论/动态）的权限与端点同源判定：
          # 传下去后 payload 用同一批 Canaid 谓词（can_manage_project? / can_manage_team?
          # / can_archive_project? / can_export_project? / can_read_project?），
          # 与原生 /projects 行菜单逐项对齐。不传 = 全部 enabled:false（显式留白）。
          current_user: current_user
        )
      end

      # json 出口：/eln_project_list → /eln_project_list.json（幂等，重复调用不会追加）
      def json_self_path
        base = request.path.to_s.sub(/\.json\z/, '')
        "#{base}.json"
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
