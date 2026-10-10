# frozen_string_literal: true

module Lists
  # 工作区（Team）列表行序列化（ADR-0034 rev3）。
  #
  # 属性名与前端 addons/eln_ui/app/javascript/vue/teams/table.vue 的 columnDefs.field
  # 一一对应（栈的 formatData 会把 attributes 摊平到行对象上）：
  #   name / id / created_by / created_at / role / members_count / can_manage /
  #   members_url / can_leave / leave_url
  #
  # 派生值（created_by / role / members_count）优先读 Lists::TeamsService 在 SQL 里
  # 选出的别名，读不到才回退模型方法——回退路径保证本 serializer 单独使用时也不会炸。
  class TeamSerializer < ActiveModel::Serializer
    include Rails.application.routes.url_helpers
    include Canaid::Helpers::PermissionsHelper

    attributes :name, :created_by, :created_at, :role, :members_count,
               :can_manage, :members_url, :can_leave, :leave_url

    def name
      object.name
    end

    # 真源 = users.full_name；空值回退 na 文案
    def created_by
      object[:created_by_name].presence ||
        object.created_by&.full_name.presence ||
        I18n.t('users.settings.teams.index.na')
    end

    # 服务端固定格式，避免客户端时区/格式分叉（rev2 决策）
    def created_at
      object.created_at.strftime('%Y-%m-%d %H:%M')
    end

    def role
      object[:current_user_role_name].presence ||
        current_user_assignment&.user_role&.name.presence ||
        I18n.t('users.settings.teams.index.na')
    end

    def members_count
      object[:members_count] || object.users.count
    end

    # 与 load_team 的准入门槛同源：可管理 或 实例级系统管理员 bypass，
    # 避免渲染出点进去 403 的名称链接。
    def can_manage
      can_manage_team?(object) || system_admin_bypass?
    end

    def members_url
      members_users_settings_team_path(object)
    end

    # 「能否退出」必须与 UserTeamsController#destroy 的后端判定完全一致（同一事实只许
    # 一个真源）：最后一个持有 TeamPermissions::USERS_MANAGE 的人不可退出。
    # 注意不要按 UserRole.owner_role 去判——其一它返回 id 为空的未持久化对象
    #（宿主 Bug，where 会退化成 user_role_id IS NULL）；其二 Owner 名字覆盖不到
    # 那些带 team_manage 的自定义角色。
    def can_leave
      return false if current_user_assignment.blank?

      !current_user_assignment.last_with_permission?(TeamPermissions::USERS_MANAGE)
    end

    def leave_url
      return nil if current_user_assignment.blank?

      leave_user_team_html_path(current_user_assignment, format: :json, leave: true)
    end

    private

    # AMS 0.10 下 scope 可能是 options 哈希（render json: ..., user: current_user），
    # 也可能直接是 scope 对象，两种都兼容。
    def current_user
      scope.is_a?(Hash) ? scope[:user] : scope
    end

    # user_assignments（含 user_role）已由 TeamsService 预加载，这里是内存查找，无查询。
    def current_user_assignment
      return @current_user_assignment if defined?(@current_user_assignment)

      user = current_user
      @current_user_assignment =
        user.nil? ? nil : object.user_assignments.find { |assignment| assignment.user_id == user.id }
    end

    def system_admin_bypass?
      current_user&.respond_to?(:system_admin?) && current_user&.system_admin?
    end
  end
end