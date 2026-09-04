# frozen_string_literal: true

require 'rails_helper'

# 回归锁：ProjectInsights 独立页面 /insights 在 <head> 注入 insights_charts JS。
# 注入点由 widget partial 的视图上下文 content_for(:head) 完成（已消除高危的
# 控制器层 view_flow 触达）；项目级过滤（?project_id=）不影响注入逻辑。
#
# 重要：test 环境 webpacker manifest 缺失，故 stub javascript_include_tag，
# 仅验证"注入逻辑生效、独立页面正常渲染 200"，真实 JS 打包加载需
# dev/prod 构建 webpack 后手动访问 /insights 验证。
RSpec.describe 'ProjectInsights index page', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, confirmed_at: Time.zone.now) }

  before(:all) do
    User.__send__(:define_method, :send_devise_notification) { |*_args| true }
  end

  before do
    create(:team, :change_user_team, created_by: user)
    # 仅在 enabled? 为真时注入，故先启用才能复现/锁定。
    AddonSetting.create!(name: 'project_insights', enabled: true, configuration: {})
    allow_any_instance_of(ActionView::Base)
      .to receive(:javascript_include_tag)
      .and_return('<script src="/packs-test/insights_charts.js"></script>')
    sign_in user
  end

  it 'renders the insights page 200 with insights_charts injected into <head>' do
    get '/insights'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('insights_charts.js')
  end

  it 'is forbidden when the addon is disabled' do
    AddonSetting.find_by(name: 'project_insights')&.update!(enabled: false)
    get '/insights'
    expect(response).to have_http_status(:forbidden)
  end
end
