# frozen_string_literal: true

require 'rails_helper'

# 下钻联动（P8）后端：验证 addon decorator 在 enabled? 时把 widget 下钻参数
# 翻译成 current_tasks 过滤，且过滤边界与 AggregatorService 的分桶完全一致。
# 断言以「匹配任务数」为准：current_tasks#show 返回各任务的渲染片段，
# 片段内容在 controller spec 下为空，但 data 数组长度即匹配数，足以验证过滤。
describe Dashboard::CurrentTasksController, type: :controller do
  # test 环境 mailer from 为空，create(:user) 触发的 Devise 确认邮件会抛
  # ArgumentError: SMTP From address may not be blank。stub 掉通知发送以规避环境缺陷。
  before(:each) do
    allow_any_instance_of(User).to receive(:send_devise_notification)
  end
  login_user
  include_context 'reference_project_structure'

  before(:all) { MyModuleStatusFlow.ensure_default }

  before do
    allow(Scinote::ProjectInsights).to receive(:enabled?).and_return(true)
  end

  let(:status) { MyModuleStatus.first }

  def matched_count
    JSON.parse(response.body)['data'].size
  end

  describe 'due_bucket 下钻过滤（对齐 AggregatorService#due_dates）' do
    let!(:overdue_task) do
      create(:my_module, experiment: experiment, my_module_status: status, due_date: 2.days.ago)
    end
    let!(:upcoming_task) do
      create(:my_module, experiment: experiment, my_module_status: status, due_date: 10.days.from_now)
    end

    it 'due_bucket=overdue 仅返回逾期任务' do
      get :show, params: { project_id: project.id, due_bucket: 'overdue' }, format: :json
      expect(response).to have_http_status(:success)
      expect(matched_count).to eq(1)
    end

    it 'due_bucket=upcoming 仅返回即将到来任务' do
      get :show, params: { project_id: project.id, due_bucket: 'upcoming' }, format: :json
      expect(matched_count).to eq(1)
    end
  end

  describe 'stale_bucket 下钻过滤（对齐 AggregatorService#bottlenecks，排除 completed）' do
    let!(:stale_task) do
      create(:my_module, experiment: experiment, my_module_status: status)
        .tap { |m| m.update_column(:updated_at, 100.days.ago) } # rubocop:disable Rails/SkipsModelValidations
    end
    let!(:fresh_task) do
      create(:my_module, experiment: experiment, my_module_status: status)
        .tap { |m| m.update_column(:updated_at, 1.day.ago) } # rubocop:disable Rails/SkipsModelValidations
    end

    it 'stale_bucket=thirty_plus 仅返回 default_period_days(90)+ 天未更新且未完成任务' do
      get :show, params: { project_id: project.id, stale_bucket: 'thirty_plus' }, format: :json
      expect(matched_count).to eq(1)
    end
  end

  describe 'assigned_user_id 下钻过滤（workload widget）' do
    let(:other_user) { create(:user) }
    let!(:mine) { create(:my_module, experiment: experiment, my_module_status: status) }
    let!(:theirs) { create(:my_module, experiment: experiment, my_module_status: status) }

    before do
      create :user_my_module, my_module: mine, user: user
      create :user_my_module, my_module: theirs, user: other_user
    end

    it 'assigned_user_id 仅返回指派给该用户的任务' do
      get :show, params: { project_id: project.id, assigned_user_id: user.id }, format: :json
      expect(matched_count).to eq(1)
    end
  end

  describe 'enabled? 门控' do
    let!(:overdue_task) do
      create(:my_module, experiment: experiment, my_module_status: status, due_date: 2.days.ago)
    end

    it '未启用时忽略 due_bucket 过滤（core 行为不变）' do
      allow(Scinote::ProjectInsights).to receive(:enabled?).and_return(false)
      get :show, params: { project_id: project.id, due_bucket: 'overdue' }, format: :json
      expect(response).to have_http_status(:success)
      # 未过滤：返回项目内所有可读任务（远多于 1），证明过滤器被忽略
      expect(matched_count).to be > 1
    end
  end
end
