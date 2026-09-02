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
      due_dates: { overdue: 1, due_today: 2, due_this_week: 3, upcoming: 4 }
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
      'overdue' => 1, 'due_today' => 2, 'due_this_week' => 3, 'upcoming' => 4
    )
  end

  it 'rejects an unknown kind with 400' do
    get '/insights?kind=unknown'
    expect(response).to have_http_status(:bad_request)
  end
end
