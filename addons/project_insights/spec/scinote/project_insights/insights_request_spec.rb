# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scinote::ProjectInsights JSON endpoint', type: :request do
  include Devise::Test::IntegrationHelpers

  # 测试环境未配置邮件发件人；创建已确认用户跳过 devise 确认邮件，并兜底禁用投递
  around(:each) do |example|
    original = ActionMailer::Base.perform_deliveries
    ActionMailer::Base.perform_deliveries = false
    example.run
    ActionMailer::Base.perform_deliveries = original
  end

  let(:user) { create :user, confirmed_at: Time.zone.now }
  # 给测试用户一个真实当前团队（addon 端点需要团队上下文；dashboard 实际也总是带 current_team 渲染）。
  let(:team) { create :team, created_by: user, skip_user_assignments: true }
  let!(:owner_role) { UserRole.find_by(name: I18n.t('user_roles.predefined.owner')) }
  let!(:team_assignment) { create :user_assignment, user: user, assignable: team, user_role: owner_role }
  let(:fake_service) do
    instance_double(
      Scinote::ProjectInsights::AggregatorService,
      status_overview: [{ id: 1, name: 'A', color: '#ffffff', count: 2 }],
      workload: [{ user_id: 1, user_name: 'X', status_id: 1, status_name: 'A', status_color: '#ffffff', count: 1 }],
      bottlenecks: { seven: 1, fourteen: 2, thirty_plus: 3 },
      due_dates: { overdue: 1, today: 2, tomorrow: 3, this_week: 4, next_week: 5 }
    )
  end

  before do
    user.update!(current_team_id: team.id)
    user.confirm
    sign_in user
    allow(Scinote::ProjectInsights::AggregatorService).to receive(:new).and_return(fake_service)
  end

  it 'returns status overview for kind=status' do
    get '/insights?kind=status'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      [{ 'id' => 1, 'name' => 'A', 'color' => '#ffffff', 'count' => 2 }]
    )
  end

  it 'returns workload for kind=workload' do
    get '/insights?kind=workload'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first['user_name']).to eq 'X'
  end

  it 'returns bottlenecks for kind=bottlenecks' do
    get '/insights?kind=bottlenecks'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('seven' => 1, 'fourteen' => 2, 'thirty_plus' => 3)
  end

  it 'returns due_dates for kind=due_dates' do
    get '/insights?kind=due_dates'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'overdue' => 1, 'today' => 2, 'tomorrow' => 3, 'this_week' => 4, 'next_week' => 5
    )
  end

  it 'rejects an unknown kind with 400' do
    get '/insights?kind=unknown'
    expect(response).to have_http_status(:bad_request)
  end

  it 'scopes aggregation by project_id when provided' do
    project = create(:project, team: team, created_by: user, default_public_user_role_id: team_assignment.user_role.id)
    expect(Scinote::ProjectInsights::AggregatorService)
      .to receive(:new).with(user, team, project).and_return(fake_service)
    get "/insights?kind=status&project_id=#{project.id}"
    expect(response).to have_http_status(:ok)
  end

  describe 'GET /insights/tasks (per-bucket task list, 待补 G)' do
    let(:fake_service) do
      instance_double(
        Scinote::ProjectInsights::AggregatorService,
        status_overview: [], workload: [], bottlenecks: {}, due_dates: {},
        tasks_for: [{ id: 1, name: 'Task A', status_name: 'A', status_color: '#fff',
                      date: '2026-01-01T00:00:00Z', assigned_user_names: %w(X) }]
      )
    end

    it 'returns the bucket task list' do
      get '/insights/tasks?kind=due_dates&bucket=overdue'
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first['name']).to eq 'Task A'
    end

    it 'rejects a missing bucket with 400' do
      get '/insights/tasks?kind=due_dates'
      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects an unsupported kind with 400' do
      get '/insights/tasks?kind=status&bucket=overdue'
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'GET /insights?kind=workload&member_ids (D 可交互成员多选)' do
    # 用可控 instance_double 验证端点把 member_ids 透传给 workload（红→绿前先写好断言）。
    let(:svc) do
      double = instance_double(Scinote::ProjectInsights::AggregatorService)
      allow(double).to receive(:workload).with(member_ids: [1]).and_return(
        [{ user_id: 1, user_name: 'X', status_id: 1, status_name: 'A', status_color: '#fff', count: 1 }]
      )
      allow(double).to receive(:workload).with(member_ids: nil).and_return([])
      allow(double).to receive(:status_overview).and_return([])
      allow(double).to receive(:bottlenecks).and_return({})
      allow(double).to receive(:due_dates).and_return({})
      allow(double).to receive(:tasks_for).and_return([])
      double
    end

    before do
      allow(Scinote::ProjectInsights::AggregatorService).to receive(:new).and_return(svc)
    end

    it 'forwards member_ids to workload and returns filtered data' do
      get '/insights?kind=workload&member_ids[]=1'
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first['user_id']).to eq 1
    end

    it 'does not 400 when member_ids is given for a non-workload kind' do
      get '/insights?kind=status&member_ids[]=1'
      expect(response).to have_http_status(:ok)
    end
  end
end
