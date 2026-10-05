# frozen_string_literal: true

# access_control addon —— 自动化测试基础设施
#
# ## 为什么不用上游的 rspec
# 两个实测出来的硬障碍：
#   1. 生产镜像 `bundle config set without 'development test'` —— rspec / factory_bot /
#      shoulda-matchers / database_cleaner / webmock 等 test group 的 gem **根本没装**
#      （`bundle list` 里测试相关的只有 minitest）。
#   2. 上游 addon spec 靠 `config/initializers/load_addons_specs.rb` 把
#      `addons/<name>/spec` **符号链接**到 `spec/addons/<name>` 来让 rspec 发现，
#      而 Windows 下 symlink 建不起来 —— boot 日志明确打印
#      `[SciNote] Unable to load specs from addons! Your system does not support symlink!`
# 所以走 minitest：随 Rails 自带、零额外依赖、能被 CI 直接调起。
#
# ## 跑法
#   RAILS_ENV=test bin/rails runner addons/access_control/test/run.rb
#
# ## 隔离策略
#   - 列 / 角色 / seed admin 属于「环境」，在 run.rb 里事务外一次性准备（幂等）。
#   - 每个 test 自己建的数据用事务包住跑完即回滚（见 AcTest::Base#run），
#     所以测试可反复跑、互不污染，也不依赖生产库里的真人账号
#     （旧 loop_*.rb 直接引用 user id 1/34/35，那是不可重复的）。

require 'minitest/autorun'

module AcTest
  # 角色定义真源 —— 从生产库导出。
  # addon 里所有角色都是 `UserRole.find_by(name: ..., predefined: false)`，
  # **不认 id**，所以测试自建同名角色即可，不需要复用生产的 49~54 号 id。
  # （顺带纠正：生产库实际是 50=self_only_researcher / 51=experiment_owner，
  #   与早期记忆里记的相反 —— 但代码不依赖 id，无影响。）
  CUSTOM_ROLES = {
    'experiment_owner' => %w[
      experiment_none experiment_users_manage experiment_tasks_create experiment_read
      experiment_read_archived experiment_read_canvas experiment_manage
      experiment_activities_read experiment_users_read
    ],
    'self_only_researcher' => %w[
      project_read project_read_archived project_activities_read project_users_read
      project_comments_read project_comments_create project_comments_manage_own
      project_tags_manage project_experiments_create
    ],
    'task_owner' => %w[
      task_read task_read_archived task_manage task_activities_read task_users_read
      task_comments_create task_none task_comments_manage_own task_tags_manage
      task_share task_update_start_date task_update_due_date task_update_description
      task_results_manage task_results_comments_manage_own task_results_comments_create
      task_protocol_manage task_steps_manage task_complete task_update_status
      task_steps_complete task_steps_uncomplete task_steps_skip task_steps_unskip
      task_steps_checklist_check task_steps_checklist_uncheck
      task_steps_comments_create task_steps_comments_delete_own
      task_steps_comments_update_own task_repository_rows_assign
      task_repository_rows_manage task_stock_consumption_update task_users_manage
      task_comments_manage task_results_delete_archived task_results_comments_manage
      task_steps_comments_delete task_steps_comments_update
      task_designated_users_manage
    ],
    'project_head' => %w[
      project_read project_read_archived project_manage project_activities_read
      project_users_read project_users_manage project_comments_read
      project_comments_create project_comments_manage_own project_comments_manage
      project_tags_manage project_experiments_create experiment_read
      experiment_read_archived experiment_users_read experiment_users_manage
      task_users_read task_users_manage task_designated_users_manage
    ],
    'WL-实验可见(含画布)' => %w[experiment_read experiment_read_canvas],
    'WL-实验+任务可见' => %w[experiment_read experiment_read_canvas task_read]
  }.freeze

  class << self
    # 一次性准备环境（事务外，幂等）
    def prepare!
      ensure_strategy_column!
      ensure_predefined_roles!
      seed_admin!
      ensure_custom_roles!
    end

    # 本实例的 addon 迁移跑不通（db:migrate 被 2 个 down 的 ai_eln 迁移卡住），
    # 生产库当年是裸 SQL 加的列 —— test 库同样处理。
    def ensure_strategy_column!
      return if ActiveRecord::Base.connection.columns(:projects).map(&:name)
                                  .include?('experiment_visibility_strategy')

      ActiveRecord::Base.connection.add_column(
        :projects, :experiment_visibility_strategy, :integer, default: 0, null: false
      )
      Project.reset_column_information
    end

    def ensure_predefined_roles!
      %i[owner_role normal_user_role technician_role viewer_role].each do |m|
        role = UserRole.public_send(m)
        UserRole.find_by(name: role.name, predefined: true) ||
          UserRole.create!(name: role.name,
                           permissions: role.permissions,
                           predefined: true)
      end
    end

    # non-predefined 角色必须带 created_by / last_modified_by —— 这个账号要活得比
    # 单个 test 的事务久，所以在事务外建（幂等，按 email 找）。
    def seed_admin!
      @seed_admin ||= begin
        u = User.find_by(email: 'ac_test_seed@localhost')
        u || User.create!(email: 'ac_test_seed@localhost',
                          password: 'Password123!',
                          full_name: 'AC Test Seed',
                          initials: 'ATS',
                          confirmed_at: Time.zone.now)
      end
    end

    def ensure_custom_roles!
      CUSTOM_ROLES.each do |name, perms|
        next if UserRole.exists?(name: name, predefined: false)

        UserRole.create!(name: name,
                         permissions: perms,
                         predefined: false,
                         created_by: seed_admin!,
                         last_modified_by: seed_admin!)
      end
    end

    def role(name)
      UserRole.find_by(name: name, predefined: false)
    end
  end

  # 所有 access_control 测试的基类。
  # 每个 test 包在一个事务里，跑完强制 Rollback —— 不依赖 ActiveSupport::TestCase
  # 的 fixture 机制（上游 fixtures 在 runner 下未必就绪），自己管最可控。
  class Base < Minitest::Test
    def run(*args)
      result = nil
      ActiveRecord::Base.transaction do
        result = super
        raise ActiveRecord::Rollback
      end
      result
    end

    private

    # ---------- 工厂 ----------
    #
    # ⚠ 顺序有讲究：Team 是 top_level_assignable，after_create 会跑
    #   `create_user_assignments!(user = created_by)`（assignable.rb:145），
    #   created_by 为 nil 会直接炸 `Validation failed: User must exist`。
    #   所以必须「先有 user，再拿它当 created_by 建 team」，最后才把人加进 team。

    def make_team!(creator: nil, name: nil)
      Team.create!(name: name || "AC team #{SecureRandom.hex(4)}",
                   created_by: creator,
                   last_modified_by: creator)
    end

    def make_user!(name: 'member')
      User.create!(email: "ac_#{name}_#{SecureRandom.hex(6)}@localhost",
                   password: 'Password123!',
                   full_name: "AC #{name}",
                   initials: name[0, 3].upcase.ljust(2, 'X'),
                   confirmed_at: Time.zone.now)
    end

    # ⚠ 这个版本**没有 user_teams 表**：团队 membership 就是一条
    #   UserAssignment(assignable: Team)（User 侧 `has_many :teams, through:
    #   :user_assignments, source_type: 'Team'`）。所以「加入团队」= 建 UA，不是建 UserTeam。
    # ⚠ permission_granted? 以 user.permission_team（= @permission_team || current_team）
    #   为作用域，不设 current_team_id 会恒 false。
    def join_team!(user, team)
      existing = UserAssignment.find_by(assignable_type: 'Team',
                                        assignable_id: team.id,
                                        user_id: user.id)
      if existing.nil?
        UserAssignment.create!(user: user,
                               assignable: team,
                               user_role: UserRole.find_predefined_normal_user_role,
                               team: team,
                               assigned: :manually)
      end
      user.update_column(:current_team_id, team.id)
      user
    end

    # 一把搭出「团队 + creator（已入队）+ 项目」的最小场景
    def build_scene!(visibility: :hidden, strategy: nil)
      creator = make_user!(name: 'creator')
      team    = make_team!(creator: creator)
      join_team!(creator, team)
      project = make_project!(team: team, creator: creator,
                              visibility: visibility, strategy: strategy)
      { team: team, creator: creator, project: project }
    end

    # 把一个人加进项目（建 Project 级 UA 并同步下放）。
    # role: :normal     —— 预定义 User 角色（原生 User 角色本身就含 experiment_read）
    #       :restricted —— self_only_researcher，不含 experiment_read，
    #                      正是「看得见项目、看不见实验」的矩阵目标人群。
    def add_member!(project, team, assigner:, role: :normal, name: 'member')
      member    = join_team!(make_user!(name: name), team)
      user_role = case role
                  when :restricted then AcTest.role('self_only_researcher')
                  else UserRole.find_predefined_normal_user_role
                  end
      ua = project.user_assignments.find_or_initialize_by(user: member, team: team)
      ua.update!(user_role: user_role, assigned: :manually)
      UserAssignments::PropagateAssignmentJob.perform_now(ua, assigner_id: assigner.id)
      member
    end

    def add_restricted_member!(project, team, assigner:, name: 'restricted')
      add_member!(project, team, assigner: assigner, role: :restricted, name: name)
    end

    def make_project!(team:, creator:, visibility: :hidden, strategy: nil)
      p = Project.new(name: "AC project #{SecureRandom.hex(4)}",
                      team: team,
                      created_by: creator,
                      last_modified_by: creator,
                      visibility: visibility)
      p.experiment_visibility_strategy = strategy if strategy
      p.save!
      p
    end

    # ⚠ test 环境里 job 是「入队不执行」（日志可见 INSERT INTO delayed_jobs），
    #   所以建完对象必须显式 perform_now，否则 D2 的策略拦截根本不会被触发。
    def make_experiment!(project:, creator:, name: nil, run_inherit: true)
      e = Experiment.new(name: name || "AC exp #{SecureRandom.hex(4)}",
                         project: project,
                         created_by: creator,
                         last_modified_by: creator)
      e.save!
      UserAssignments::InheritUserAssignmentsJob.perform_now(e, assigner_id: creator.id) if run_inherit
      e
    end

    # ⚠ MyModule 校验「同一实验内 x/y 不能重复」，所以坐标必须递增分配，
    #   不能固定 0,0（建第二个任务就会 RecordInvalid）。
    def make_task!(experiment:, creator:, name: nil, run_inherit: true)
      x = experiment.my_modules.maximum(:x).to_i + 1
      t = MyModule.create!(name: name || "AC task #{SecureRandom.hex(4)}",
                           experiment: experiment,
                           created_by: creator,
                           last_modified_by: creator,
                           x: x, y: 0)
      UserAssignments::InheritUserAssignmentsJob.perform_now(t, assigner_id: creator.id) if run_inherit
      t
    end

    # ---------- 断言辅助 ----------
    def can_read?(obj, user)
      obj.readable_by_user?(user)
    end

    def ua_for(obj, user)
      UserAssignment.find_by(assignable_type: obj.class.name,
                             assignable_id: obj.id,
                             user_id: user.id)
    end

    def matrix(project)
      Scinote::AccessControl::VisibilityMatrixService.call(project)
    end

    def cell(project, user, experiment)
      matrix(project)[:cells]["#{user.id}-#{experiment.id}"] || {}
    end

    def grant!(experiment, user, scope: :experiment)
      experiment.send(:grant_member_visibility!, user, scope: scope)
    end

    def revoke!(experiment, user, scope: :experiment)
      experiment.send(:revoke_member_visibility!, user, scope: scope)
    end
  end
end
