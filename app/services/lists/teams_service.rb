# frozen_string_literal: true

module Lists
  # 工作区（Team）列表数据源（ADR-0034 rev3）。
  #
  # 契约：请求 { page, per_page, order: {column, dir}, search, view_mode, filters }
  #      → 响应 { data: [{id, type, attributes}], meta: {total_pages, total_count, filtered_count} }
  #   这是宿主 shared/datatable 栈（table.vue 的 loadData / formatData）的原生协议，
  #   前端 addons/eln_ui/app/javascript/vue/teams/table.vue 只做 AG Grid 薄封装。
  #
  # 排序 colId = 前端 columnDefs.field ∈ {name, id, created_by, created_at, role, members_count}。
  class TeamsService < BaseService
    # 对齐 shared/datatable 的每页条数下拉（perPageOptions）
    PER_PAGE_OPTIONS = [10, 20, 50, 100].freeze
    DEFAULT_PER_PAGE = 20

    def initialize(raw_data, params, user:)
      super(raw_data, params, user: user)
      @current_user_id = user&.id
    end

    private

    # 派生列（创建人 / 当前用户角色 / 成员数）一律用「相关标量子查询」，不用 JOIN：
    #   * JOIN user_assignments 会按该工作区的**全部成员**展开行数 ⇒ 破坏分页与计数；
    #   * JOIN users 做聚合需要 GROUP BY ⇒ 与 Kaminari 的 count 打架。
    # 子查询保证「一行一 team」；而 Kaminari 取 total_count 时 Rails 会把整个 SELECT
    # 换成 COUNT(*)，这些派生列自动退出语句，不影响计数语义与性能。
    def fetch_records
      @records = @raw_data
                .includes(:created_by, :user_assignments => :user_role)
                .select('teams.*')
                .select("(#{created_by_name_sql}) AS created_by_name")
                .select("(#{current_user_role_name_sql}) AS current_user_role_name")
                .select("(#{members_count_sql}) AS members_count")
    end

    def filter_records
      return if @params[:search].blank?

      @records = @records.where_attributes_like(['teams.name'], @params[:search])
    end

    # 无 order 时默认按名称升序：栈首次加载 order 为 null（table.vue 的 order 初值），
    # 而原生 TeamsDatatable 缺省亦为 name asc。不能沿用基类「blank 即不排序」，
    # 否则首屏行序未定义（与 rev3 实测基线不一致）。
    def sort_records
      return super if @params[:order].present?

      @records = @records.order(Arel.sql('LOWER(teams.name)')).order(:id)
    end

    # 值既可是真实列（'teams.name'），也可为 fetch_records 的输出别名
    #（created_by_name / current_user_role_name / members_count）——
    # PostgreSQL 的 ORDER BY 允许以标识符引用输出列，故创建人/角色/成员数排序同样下推 SQL。
    # 基类会在其后追加 .order(:id) 作稳定兜底。
    def sortable_columns
      @sortable_columns ||= {
        name: 'teams.name',
        id: 'teams.id',
        created_by: 'created_by_name',
        created_at: 'teams.created_at',
        role: 'current_user_role_name',
        members_count: 'members_count'
      }
    end

    # per_page / page 在此兜住：栈的下拉是 [10,20,50,100]，非法值不能让
    # Kaminari 落到 .per(0)（报错）或 .per(-1)（视作无限制 ⇒ 全表拉取）。
    def paginate_records
      @records = @records.page(sanitized_page).per(sanitized_per_page)
    end

    def sanitized_page
      requested = @params[:page].to_i
      requested < 1 ? 1 : requested
    end

    def sanitized_per_page
      requested = @params[:per_page].to_i
      PER_PAGE_OPTIONS.include?(requested) ? requested : DEFAULT_PER_PAGE
    end

    # 真源 = users.full_name（Team belongs_to :created_by, optional: true）
    def created_by_name_sql
      'SELECT users.full_name FROM users WHERE users.id = teams.created_by_id'
    end

    # 当前用户在该工作区的角色。限定 user_id，故与「该工作区有多少成员」无关。
    def current_user_role_name_sql
      <<~SQL.squish
        SELECT user_roles.name
        FROM user_assignments
        INNER JOIN user_roles ON user_roles.id = user_assignments.user_role_id
        WHERE user_assignments.assignable_id = teams.id
          AND user_assignments.assignable_type = 'Team'
          AND user_assignments.user_id = #{quoted(@current_user_id)}
      SQL
    end

    # 成员数口径必须与 Assignable#users（app/models/concerns/assignable.rb:29-42）
    # 保持一致：直连成员 ∪ 用户组成员 ∪ 上级团队成员。
    # ⚠️ 改动此 SQL 必须同步 Assignable#users，否则列表成员数与 elsewhere 分叉。
    def members_count_sql
      <<~SQL.squish
        SELECT COUNT(DISTINCT users.id) FROM users WHERE (
          users.id IN (
            SELECT user_assignments.user_id FROM user_assignments
            WHERE user_assignments.assignable_id = teams.id
              AND user_assignments.assignable_type = 'Team'
          )
          OR users.id IN (
            SELECT user_group_memberships.user_id
            FROM user_group_memberships
            INNER JOIN user_group_assignments
              ON user_group_assignments.user_group_id = user_group_memberships.user_group_id
            WHERE user_group_assignments.assignable_id = teams.id
              AND user_group_assignments.assignable_type = 'Team'
          )
          OR users.id IN (
            SELECT user_assignments.user_id FROM user_assignments
            WHERE user_assignments.assignable_type = 'Team'
              AND user_assignments.assignable_id IN (
                SELECT team_assignments.team_id FROM team_assignments
                WHERE team_assignments.assignable_id = teams.id
                  AND team_assignments.assignable_type = 'Team'
              )
          )
        )
      SQL
    end

    def quoted(value)
      ActiveRecord::Base.connection.quote(value)
    end
  end
end