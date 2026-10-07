# TODO: For all permissions: foe ALL permission levels check whether they're
# archived (for restore permissions) or active (for all other permissions) -
# now we mostly do the check only for the permission level for which the
# permission was made
module Organization
  Canaid::Permissions.register_generic do
    # organization: create team
    # 仅实例级系统管理员可新建 workspace（Team）。
    # 普通用户仍可通过注册/批量建用户流程获得自己的默认私有 workspace，
    # 那条路径不经过此权限，不受影响。
    can :create_teams do |user|
      # respond_to 兜底：deploy 窗口内若 migration 尚未落地（代码先于 DB 上线），
      # 返回 false（无人可建）而非抛 NoMethodError 让创建页崩溃。
      user&.respond_to?(:system_admin?) && user.system_admin?
    end

    can :manage_label_printers do |_|
      true
    end

    can :create_acitivity_filters do
      Rails.application.config.x.webhooks_enabled
    end

    can :set_time_zone do |_|
      !ApplicationSettings.instance.values['security.time_zone.enforced']
    end

    can :set_date_format do |_|
      !ApplicationSettings.instance.values['security.date_format.enforced']
    end
  end
end
