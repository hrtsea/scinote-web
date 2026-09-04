# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::ProjectInsights::AggregatorService do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create :user }
  # skip_user_assignments 避免工厂自动产生无关指派，权限由下方 team_assignment 显式控制
  let(:team) { create :team, created_by: user, skip_user_assignments: true }
  let!(:owner_role) { UserRole.find_by(name: I18n.t('user_roles.predefined.owner')) }
  let!(:team_assignment) { create :user_assignment, user: user, assignable: team, user_role: owner_role }
  let(:project) { create :project, team: team, created_by: user, default_public_user_role_id: team_assignment.user_role.id }
  let(:experiment) { create :experiment, project: project, created_by: user }

  # 当前 team 自有的 in_team 状态流（含 3 个状态）
  let!(:flow) { create :my_module_status_flow, team: team, visibility: :in_team }
  let!(:status_a) { create :my_module_status, my_module_status_flow: flow }
  let!(:status_b) { create :my_module_status, my_module_status_flow: flow }
  let!(:status_c) { create :my_module_status, my_module_status_flow: flow }

  let(:service) { described_class.new(user, team) }

  # 测试环境未配置邮件发件人，禁用投递以避免 devise 确认邮件报错（与本服务无关）
  around(:each) do |example|
    original = ActionMailer::Base.perform_deliveries
    ActionMailer::Base.perform_deliveries = false
    example.run
    ActionMailer::Base.perform_deliveries = original
  end

  # 创建团队内可读任务；created_by = user 经 Assignable 继承链获得读取权限。
  # updated_at 用 update_columns 设置以绕过自动时间戳覆盖。
  def create_task(attributes = {})
    updated_at = attributes.delete(:updated_at)
    task = create(:my_module,
                  experiment: experiment,
                  created_by: user,
                  my_module_status: status_a,
                  **attributes)
    task.update_columns(updated_at: updated_at) if updated_at # rubocop:disable Rails/SkipsModelValidations
    task
  end

  describe '#status_overview' do
    it '按状态聚合并回带无任务的状态（计数 0）' do
      create_task(my_module_status: status_a)
      create_task(my_module_status: status_a)
      create_task(my_module_status: status_b)

      overview = service.status_overview
      by_id = overview.index_by { |s| s[:id] }

      expect(by_id[status_a.id][:count]).to eq 2
      expect(by_id[status_b.id][:count]).to eq 1
      expect(by_id[status_c.id][:count]).to eq 0
      expect(by_id[status_a.id][:name]).to eq status_a.name
      expect(by_id[status_a.id][:color]).to eq status_a.color
    end

    it '排除已归档任务与归档实验/项目下的任务' do
      create_task(my_module_status: status_a)
      create_task(my_module_status: status_a, archived: true)
      archived_exp = create(:experiment, project: project, created_by: user, archived: true)
      create(:my_module, experiment: archived_exp, created_by: user, my_module_status: status_a)

      overview = service.status_overview.index_by { |s| s[:id] }
      expect(overview[status_a.id][:count]).to eq 1
    end
  end

  describe '#workload' do
    it '按 指派用户 × 状态 聚合' do
      u1 = create :user
      u2 = create :user
      t1 = create_task(my_module_status: status_a)
      t2 = create_task(my_module_status: status_b)
      t1.designated_users << u1
      t1.designated_users << u2
      t2.designated_users << u1

      rows = service.workload.map { |r| [r[:user_id], r[:status_id], r[:count]] }.sort
      expect(rows).to eq(
        [
          [u1.id, status_a.id, 1],
          [u1.id, status_b.id, 1],
          [u2.id, status_a.id, 1]
        ].sort
      )
    end

    # D 可交互成员多选：按所选成员过滤，仅返回所选成员的行。
    it 'member_ids 仅返回所选成员的行' do
      u1 = create :user
      u2 = create :user
      t1 = create_task(my_module_status: status_a)
      t2 = create_task(my_module_status: status_b)
      t1.designated_users << u1
      t2.designated_users << u2

      rows = service.workload(member_ids: [u1.id]).map { |r| [r[:user_id], r[:status_id]] }.sort
      expect(rows).to eq [[u1.id, status_a.id]].sort
      expect(rows.pluck(0)).not_to include(u2.id)
    end

    it 'member_ids 为空数组时返回全部成员' do
      u1 = create :user
      u2 = create :user
      t1 = create_task(my_module_status: status_a)
      t1.designated_users << u1
      t1.designated_users << u2
      rows = service.workload(member_ids: []).pluck(:user_id)
      expect(rows.sort).to eq [u1.id, u2.id].sort
    end
  end

  describe '#bottlenecks' do
    it '按 7/14/<period>+ 天未更新分桶并排除 completed? 任务（默认 period=90）' do
      create_task(updated_at: 10.days.ago)  # seven
      create_task(updated_at: 40.days.ago)  # fourteen（14-90 天）
      create_task(updated_at: 100.days.ago) # thirty_plus（>90 天）
      create_task(updated_at: 3.days.ago)   # 近期，不在任何桶
      create_task(updated_at: 40.days.ago, state: :completed, completed_on: Time.current)

      result = service.bottlenecks
      expect(result[:seven]).to eq 1
      expect(result[:fourteen]).to eq 1
      expect(result[:thirty_plus]).to eq 1
    end

    it '尊重实例配置的 default_period_days 作为 thirty_plus 阈值' do
      AddonSetting.for('project_insights').update!(configuration: { 'default_period_days' => '30' })
      create_task(updated_at: 40.days.ago) # >30 天 → thirty_plus
      create_task(updated_at: 20.days.ago) # 14-30 天 → fourteen
      result = service.bottlenecks
      expect(result[:fourteen]).to eq 1
      expect(result[:thirty_plus]).to eq 1
    ensure
      AddonSetting.for('project_insights').update!(configuration: {})
    end
  end

  describe '#due_dates' do
    # 档位按「周」切分（end_of_week），故冻结到本周周三正午，
    # 保证 this_week 档始终有可用的测试日期（不受运行当天星期影响）。
    around(:each) do |example|
      travel_to(Time.current.utc.beginning_of_week(:monday) + 2.days + 12.hours) { example.run }
    end

    it '五档现算（UTC）并排除无 due_date 的任务；更晚截止归入 next_week 兜底' do
      today_d = Time.current.utc.to_date
      create_task(due_date: 2.days.ago)                             # overdue（早于今天）
      create_task(due_date: Time.current.utc.end_of_day - 1.minute) # today（当天）
      create_task(due_date: today_d + 1)                            # tomorrow
      create_task(due_date: today_d + 2)                            # this_week（> 明天 且本周内）
      create_task(due_date: today_d + 30)                           # next_week（兜底档）
      create_task(due_date: nil)                                    # 不计入

      result = service.due_dates
      expect(result[:overdue]).to eq 1
      expect(result[:today]).to eq 1
      expect(result[:tomorrow]).to eq 1
      expect(result[:this_week]).to eq 1
      expect(result[:next_week]).to eq 1
    end

    it 'UTC 边界：未来 1 秒归入 today（属当天，不算 overdue）' do
      create_task(due_date: 1.second.from_now)
      expect(service.due_dates[:today]).to eq 1
    end

    it 'UTC 边界：昨天 23:59 归入 overdue' do
      create_task(due_date: 1.day.ago.end_of_day)
      expect(service.due_dates[:overdue]).to eq 1
    end
  end

  describe '#tasks_for' do
    # 档位按「周」切分，冻结到本周周三，保证 this_week 档可测（对齐 #due_dates）。
    around(:each) do |example|
      travel_to(Time.current.utc.beginning_of_week(:monday) + 2.days + 12.hours) { example.run }
    end

    it 'returns task payloads for the overdue bucket (due_dates)' do
      t = create_task(due_date: 2.days.ago)
      create_task(due_date: Time.current.utc.to_date + 30) # next_week, excluded
      tasks = service.tasks_for(:due_dates, :overdue)
      expect(tasks.pluck(:id)).to eq [t.id]
      expect(tasks.first).to include(name: t.name,
                                     status_name: status_a.name,
                                     status_color: status_a.color)
      expect(tasks.first[:date]).to eq t.due_date.iso8601
    end

    it 'returns tasks for the seven bucket (bottlenecks), excluding completed' do
      t = create_task(updated_at: 10.days.ago)
      create_task(updated_at: 10.days.ago, state: :completed, completed_on: Time.current)
      tasks = service.tasks_for(:bottlenecks, :seven)
      expect(tasks.pluck(:id)).to eq [t.id]
    end

    it 'returns [] for an unsupported kind' do
      expect(service.tasks_for(:status, :overdue)).to eq []
    end

    it 'bucket list sizes are consistent with the aggregation counts' do
      create_task(updated_at: 10.days.ago)
      create_task(updated_at: 40.days.ago)
      create_task(updated_at: 100.days.ago)
      listed = %i(seven fourteen thirty_plus).sum { |b| service.tasks_for(:bottlenecks, b).size }
      expect(listed).to eq service.bottlenecks.values.sum
    end
  end

  describe 'project scoping' do
    let(:project2) { create :project, team: team, created_by: user, default_public_user_role_id: team_assignment.user_role.id }
    let(:experiment2) { create :experiment, project: project2, created_by: user }
    let(:service_p) { described_class.new(user, team, project2) }

    it 'aggregates only the tasks within the given project' do
      create(:my_module, experiment: experiment, created_by: user, my_module_status: status_a)
      create(:my_module, experiment: experiment2, created_by: user, my_module_status: status_a)
      expect(service.status_overview.sum { |s| s[:count] }).to eq 2
      expect(service_p.status_overview.sum { |s| s[:count] }).to eq 1
    end

    it 'team-scoped service still aggregates across all projects' do
      create(:my_module, experiment: experiment2, created_by: user, my_module_status: status_b)
      expect(service.status_overview.sum { |s| s[:count] }).to eq 1
    end
  end
end
