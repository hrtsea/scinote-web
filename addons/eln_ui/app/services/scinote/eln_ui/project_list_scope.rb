# frozen_string_literal: true

# ELN UI —— 项目列表 **唯一真源** scope（V1.27）
#
# ## 为什么要有这么一个类（不是"抽个工具方法好看"）
#   要守的不变式是「**工作台卡片数字 ≡ 点进去项目列表页筛出来的条数**，逐位一致」
#   （spec SCN-DASH-8 同源要求）。该不变式唯一的实现方式，是让两侧走**同一段可变代码** ——
#   同一段代码被改动时两侧同增同减，否则必然分叉。
#
#   本项目已经**两次**因为「同一件事两份定义」出事：
#     · 工作台与资源中心两套花费口径（差一分钱就是当面打脸）；
#     · 前端两套路径词汇表（改了一侧忘另一侧 → 点击静默无反应 / 真机 404）。
#   所以本次把「项目列表页看到哪些项目」收敛成**这一个类**，被两处共用：
#     · 项目列表页 controller（ProjectListController#scoped_projects）；
#     · 工作台「参与项目」卡片（WorkbenchPayload#participation_kpi）。
#   ⚠ 任何一处再自己写一遍 WHERE，就是第三次复发，明令禁止。
#
# ## 为什么不能只做「逐字照抄一份公式」
#   难点在**差一条就错**（生产只读探针实测）：
#     · 漏 `template: [false, nil]` —— projects.template 是**可空布尔**，生产 159 行里
#       158 行是 NULL，写 `template: false` 会把这 158 行全排掉 → 数字直接崩；
#     · 漏 `.active` —— 实测算出 288，而真机 HTTP 是 287，差 1；
#     · 漏 `.distinct` —— join user_assignments 后行数被放大。
#   这类差异单靠人工对齐抓不住，必须有单一入口。
#
# ## 交叉引用（别删）
#   `member_filtered` 复用原生 `Lists::ProjectsService#filter_project_records`（不新写 join），
#   成员筛选的**唯一真源**就是它那第 91 行：
#     `records.joins(:user_assignments).where(user_assignments: { user_id: @filters[:members] })`
#
#   ⚠ `Project#user_assignments` 是 `has_many :user_assignments, as: :assignable`
#     （concerns/assignable.rb:11）—— `joins(:user_assignments)` 会**自动带上
#     `user_assignments.assignable_type = 'Project'`**，所以成员筛选天然限定在 Project 级。
#     UserAssignment 是本项目**最常被误用的多态表**（Team / Experiment / MyModule /
#     Project 四级共用一张表），凡涉及角色/成员判定，先问「承载面是哪一级」。
#
# ## 命名空间陷阱（铁律）
#   本文件在 `module Scinote::ElnUi` 里，引用**顶层**常量必须写 `::`
#   （宿主定义了 `Scinote::I18n`，裸写 `I18n` 会命中它）。见下方 `::Project` / `::UserAssignment` /
#   `::Lists::ProjectsService` / `::ActionController::Parameters`。
#
# ## 其它纪律
#   · 禁**类级** memo（`def self.x; @x ||=`）—— 用例之间没有事务回滚，类级 memo 会造出假绿；
#   · 不写方法级 `rescue StandardError` 静默兜底 —— 要炸就当场炸（拼错 helper 名不该被藏起来）。
module Scinote
  module ElnUi
    class ProjectListScope
      # 项目列表默认视图（原生 projects#index 同名同义）：active 默认 / archived 可选。
      DEFAULT_VIEW_MODE = 'active'

      # 角色/承载面常量（角色判定只认 name，不认 id —— 与 UserRole 的既有约定一致）。
      PROJECT_ASSIGNABLE_TYPE = 'Project'
      OWNER_ROLE_NAME = 'Owner'

      class << self
        # ------------------------------------------------------------
        # ① 底座 scope —— 列表页与工作台卡片**共用**的那一段。
        #
        # 逐字复刻重构前 `ProjectListController#scoped_projects`（L190-197）的现行为：
        #   Project.where(team_id:, template: [false, nil]).distinct
        #          .readable_by_user(user)          # 权限走原生 Canaid，不造第二套
        #          再按 view_mode 切 .archived / .active
        #
        # ⚠ 三条不能漏（见文件头）：`template: [false, nil]`、`.active/.archived`、`.distinct`。
        # ⚠ 返回**无 order/无分页**的 relation —— 卡片只要 count，列表页自己补 .order。
        # ------------------------------------------------------------
        def for_listing(team:, user:, view_mode: DEFAULT_VIEW_MODE)
          ::Project.where(team_id: team.id, template: [false, nil])
                   .distinct
                   .readable_by_user(user)
                   .then { |scope| view_mode.to_s == 'archived' ? scope.archived : scope.active }
        end

        # ------------------------------------------------------------
        # ② 叠加「成员筛选」—— 复用原生 `Lists::ProjectsService#filter_project_records`。
        #
        # 含义与原生 projects#index 的 `filters[members]` **完全同义**：
        #   records.joins(:user_assignments).where(user_assignments: { user_id: member_ids })
        # join 自动限定 `assignable_type = 'Project'`（见文件头），无需额外加条件。
        #
        # ⚠ 只传**最小 params**（仅有 members）—— 避免与 controller 的完整 params 行为分叉：
        #   `filter_project_records` 还会读 `@params[:view_mode]`（L85-86）与 `@filters[:query]`，
        #   这里它们为 nil → 两条分支都不进；view_mode 已在 `for_listing` 里落定，避免二次施加。
        # ⚠ 空成员列表 = 不做筛选（返回原 scope），不是"筛出零条"。
        # ------------------------------------------------------------
        def member_filtered(scope, team:, user:, member_ids:)
          ids = Array(member_ids).compact
          return scope if ids.blank?

          params = ::ActionController::Parameters.new(filters: { members: ids })
          service = ::Lists::ProjectsService.new(team, scope, nil, params, user: user)
          service.send(:filter_project_records, scope)
        end

        # ------------------------------------------------------------
        # ③ 「参与」= `for_listing`（列表页底座）∩ 我在该项目上有 Project 级 UserAssignment。
        #
        # 口径（用户拍板）：
        #   参与 = 项目成员（我在该项目上有 **Project 级** UserAssignment）∩ 本单位 ∩ 可读 ∩
        #          未归档（活动视图）∩ 非模板。
        # ⚠ 任一角色的 Project 级 UA 都算「参与」（Owner/User/Technician/Viewer 都算），
        #   与「负责」区分开：负责是参与的子集（见 ⑤）。
        # ------------------------------------------------------------
        def participated(team:, user:, view_mode: DEFAULT_VIEW_MODE)
          member_filtered(for_listing(team: team, user: user, view_mode: view_mode),
                          team: team, user: user, member_ids: [user.id]).distinct
        end

        # ------------------------------------------------------------
        # ④ 一次求值出两个数（「参与数 / 负责数必须同一次 scope 求值」——避免两次查询之间数据漂移）。
        #
        #   participated —— 参与数
        #   responsible  —— 负责数 ⊆ 参与数（负责 = 参与 ∩ 双轨，恒成立）
        #
        # ⚠ `.distinct.count(:id)` 而不是 `.count`：参与 scope 里有 join，直接 count 会被放大。
        # ------------------------------------------------------------
        def participation(team:, user:, view_mode: DEFAULT_VIEW_MODE)
          scope = participated(team: team, user: user, view_mode: view_mode)
          {
            participated: scope.distinct.count(:id),
            responsible: scope.where(responsible_condition(user)).distinct.count(:id)
          }
        end

        # ------------------------------------------------------------
        # ⑤ 「负责」判据（Arel）—— **双轨并集**，与 `WorkbenchPayload#project_lead?` /
        #    `#project_owner?` 同语义（生产实测：两条轨道各有一半人，只认一条必然把另一半降级）。
        #      轨一：projects.supervised_by_id == 我；
        #      轨二：我在该项目上有 **Project 级 Owner** 角色的 UserAssignment。
        #
        # ⚠ `assignable_type = 'Project'` **不能漏**（铁律：多态表必须限承载面）——
        #   漏了会把「我在某个 Team / Experiment / MyModule 上挂着 Owner」也算成项目负责，
        #   那正是 `team_admin?` 事故的同一形态（见 workbench_payload 的事故注释）。
        #
        # ⚠ 用 Arel 而不是 `scope.where(a).or(scope.where(b))`：后者对「跨关联的子查询」结构兼容性
        #   更脆；这里返回一个可直接嵌进 `.where(...)` 的 Arel 节点，简单且稳定。
        # ------------------------------------------------------------
        def responsible_condition(user)
          table = ::Project.arel_table
          owned_project_ids = ::UserAssignment
                              .where(user_id: user.id, assignable_type: PROJECT_ASSIGNABLE_TYPE)
                              .joins(:user_role)
                              .where(user_roles: { name: OWNER_ROLE_NAME })
                              .select(:assignable_id)

          table[:supervised_by_id].eq(user.id).or(table[:id].in(owned_project_ids.arel))
        end
      end
    end
  end
end
