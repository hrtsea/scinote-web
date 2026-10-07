# frozen_string_literal: true

# ELN UI —— 项目列表页的**行集合唯一真源**（V1.32 / 票 #84）
#
# ## 这个类解决什么
#   spec `SCN-PROJ-LIST-7` 要求列表在同一张表里渲染「**项目行 ∪ 文件夹行**」，
#   且**有筛选条件时只渲染项目行**。这套「什么时候并集、什么时候只剩项目」的
#   分支逻辑，原生写在 `Lists::ProjectsService#call`（`app/services/lists/projects_service.rb:22-31`）。
#
# ## 为什么不直接调原生 `Lists::ProjectsService#call`
#   `call` 里最后一步是 `paginate_records`（Kaminari `.page/.per`），而且它从
#   `@params[:per_page]` **直接读原值** —— 我们的 spec `SCN-PROJ-LIST-13` 有两条硬规矩
#   `call` 不满足：
#     · 档位只能是 `{0,20,50,100}`，非法值必须**回落 20**（不许退化成全量）；
#     · `per_page=0` 表示「全部」，而 kaminari 的 `.per(0)` 语义不是这个。
#   另外 `call` 依赖 `fetch_projects` 的那一整套 `select/group`，与我们要的行形状
#   （我们自己算实验/任务/评论数）并不一致。
#   所以这里**只借用它的过滤/排序私有方法**（`filter_project_records` /
#   `filter_project_folder_records` / `fetch_project_folders` / `sort_records`），
#   分页由 controller 自己按归一化后的档位切片（见 `ProjectListController#paged_rows`）。
#
# ## 🔴 单一真源的纪律（本项目已因「同一件事两份定义」出事三次）
#   下面 `#branch` 那三分支是**逐字复刻**原生 `call` 的第 22-31 行。它是**这段语义
#   在本仓库里唯一的第二处副本**，因此：
#     · 必须由 `test/eln_ui_project_list_rows_test.rb` 里的
#       `test_row_set_matches_native_service_call_*` 与原生 `call` 对拍（同参数下
#       行集合逐项一致）—— 原生哪天改了分支，这个用例会红；
#     · 谁要改分支，先改原生、再同步这里、最后跑那条对拍用例。
#   **不允许**在 controller / view / payload 里再写第三份「有筛选就只出项目」的判断。
#
# ## 命名空间陷阱（铁律）
#   本文件在 `module Scinote::ElnUi` 里，引用**顶层**常量必须写 `::`
#   （宿主定义了 `Scinote::I18n`，裸写 `I18n` 会命中它）。见 `::Project` /
#   `::ProjectFolder` / `::Lists::ProjectsService`。
module Scinote
  module ElnUi
    class ProjectListRows
      # 行集合的两种承载面。判别**只认 `instance_of?`**（与原生 `project?` 同款）——
      # 用 `respond_to?(:code)` 之类别的方法会把两类都判成真（两边都有 `code`）。
      PROJECT = ::Project
      FOLDER = ::ProjectFolder

      # 原生 `@filters[:folder_search]` 的键名（`app/javascript/vue/projects/list.vue:378`
      # 那个 "Look inside folders" 勾选框 → `projects.index.filters_modal.folders.label`）。
      FOLDER_SEARCH_KEY = 'folder_search'

      # 面包屑向上回溯的最大层数。正常人不会建 20 层，但**数据坏了（成环）也不能死循环**——
      # 这是防炸的硬上限，不是业务上限。
      MAX_TRAIL_DEPTH = 20

      Result = Struct.new(:rows, :project_count, :current_folder, :trail, keyword_init: true)

      class << self
        def call(team:, user:, view_mode:, params:, scope:, current_folder: nil)
          new(team: team, user: user, view_mode: view_mode, params: params,
              scope: scope, current_folder: current_folder).call
        end
      end

      def initialize(team:, user:, view_mode:, params:, scope:, current_folder: nil)
        @team = team
        @user = user
        @view_mode = view_mode
        @params = params
        # 项目侧的底座 scope 由调用方给（`ProjectListScope.for_listing(...).order(name: :asc)`）——
        # 「哪些项目可见」的唯一真源在 ProjectListScope，本类**不再写一遍 WHERE**
        # （那是工作台卡片数字 ≡ 列表条数这条不变式的命根子）。
        @scope = scope
        @current_folder = current_folder
      end

      def call
        service = ::Lists::ProjectsService.new(@team, @scope, @current_folder, @params, user: @user)

        projects = service.send(:filter_project_records, @scope)
        # 文件夹侧用原生的 `fetch_project_folders`：它顺手把 `projects_count` /
        # `folders_count` 两个 SQL 别名算出来了（原生表格「x 个项目 | y 个文件夹」
        # 就是读这两个别名，`Lists::ProjectAndFolderSerializer#folder_info`）。
        # 自己再写一遍 COUNT 就是第二份口径，且必然与原生的「不过滤归档」口径分叉。
        folders = service.send(:filter_project_folder_records, service.send(:fetch_project_folders))

        rows = sort_via_service(service, assemble(projects, folders))

        Result.new(
          rows: rows,
          project_count: rows.count { |r| r.instance_of?(PROJECT) },
          current_folder: @current_folder,
          trail: build_trail
        )
      end

      private

      def filters
        @filters ||= @params[:filters] || {}
      end

      # ------------------------------------------------------------
      # 三分支 —— **逐字复刻** `Lists::ProjectsService#call` L22-31
      #
      # | 分支            | 触发条件                                   | 行集合                                  |
      # |-----------------|--------------------------------------------|-----------------------------------------|
      # | :folder_search  | `filters[folder_search] == 'true'`         | **全部**项目行（不按当前文件夹切）      |
      # | :filtered       | `filters` 非空（除上一条外）               | **当前文件夹**内的项目行                |
      # | :union          | 没有任何筛选条件                           | 当前层项目行 **∪** 当前层子文件夹行     |
      #
      # ⚠ 三个「反直觉但必须照抄」的点（自行「修正」就会与原生的行集合分叉）：
      #   ① `folder_search` 那条**不按当前文件夹收敛** —— 它的语义是「搜索时要翻进
      #      文件夹里找」，所以是全团队范围；照抄成「当前层」会让搜索少结果。
      #   ② 有筛选条件时**只出项目行**，哪怕筛选条件与文件夹毫无关系（例如只按日期筛）。
      #      spec `SCN-PROJ-LIST-7` 第 3 条明令不得自行「修正」为仍然显示文件夹。
      #   ③ 快速搜索框（`params[:search]`）**不算**「筛选条件」——它落在 `:union` 分支，
      #      于是文件夹行仍在，只是被 `filter_project_folder_records` 按名称/`PF<id>`
      #      过滤过一遍（原名行为，别把它并进 `filters`）。
      # ------------------------------------------------------------
      def assemble(projects, folders)
        case branch
        when :folder_search
          projects.to_a
        when :filtered
          projects.where(project_folder: @current_folder).to_a
        else
          projects.where(project_folder: @current_folder).to_a +
            folders.where(parent_folder: @current_folder).to_a
        end
      end

      def branch
        return :folder_search if folder_search?

        filters.present? ? :filtered : :union
      end

      # 原生写法是 `@filters[:folder_search].present? && @filters[:folder_search] == 'true'` ——
      # 两份判断缺一不可：前端在勾选框**取消**时可能发空串（`.present?` 挡住），
      # 而 `== 'true'` 挡住 `'false'` / `'1'` 这类非真值字符串。
      def folder_search?
        raw = filters[FOLDER_SEARCH_KEY]
        raw.present? && raw.to_s == 'true'
      end

      # 排序也交给原生 `sort_records`：它内部那批 `project_*` 辅助方法对文件夹行返回
      # 哨兵元组（例如 `project_users_count` → `[1, -1]`），所以「项目 + 文件夹」混排
      # 的顺序与原生表格**逐位一致**。自己写一份 sort_by 必然在文件夹该排前还是排后上分叉。
      #
      # ⚠ `sort_records` 操作的是 service 的 `@records` 实例变量（`call` 里先赋值再排序），
      #   我们绕过 `call`，所以要先把行集合塞回 `@records` 再调 —— 与 controller 原有的
      #   三行胶水同一手法，只是这次塞进去的是**并集**。
      # ⚠ `@params[:order]` 为空时 `sort_records` 直接 return（原样返回我们的数组），
      #   此时顺序 = SQL 的 `name asc`（项目行）后接 `name asc`（文件夹行）——原生同此。
      def sort_via_service(service, rows)
        service.instance_variable_set(:@records, rows)
        service.send(:sort_records)
        Array(service.instance_variable_get(:@records))
      end

      # 面包屑：从当前文件夹往上回溯到根，返回**根 → 当前**的有序数组（不含 nil）。
      #
      # ⚠ 不用原生的 `ProjectFolder#parent_folders`：那条递归 CTE 的 `ORDER BY` 是按
      #   `selected_folders_ids` 数组整体比较排的，出来的顺序不保证根在前（两层以上就乱），
      #   而面包屑**必须**根在前。层级很浅，逐级 `parent_folder` 走反而确定。
      def build_trail
        return [] if @current_folder.blank?

        chain = []
        node = @current_folder
        while node && chain.size < MAX_TRAIL_DEPTH
          chain.unshift(node)
          node = node.parent_folder
        end
        chain
      end
    end
  end
end
