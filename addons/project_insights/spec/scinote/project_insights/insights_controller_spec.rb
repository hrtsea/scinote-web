# frozen_string_literal: true

require 'rails_helper'

# 验证 insights 数据端点在 addon 被关闭（AddonSetting 契约）时返回 403。
# 沿用本仓库 request spec 的 Devise 邮件规避手法（见其他 addon spec）。
RSpec.describe 'ProjectInsights insights endpoint', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, confirmed_at: Time.zone.now) }

  before(:all) do
    User.__send__(:define_method, :send_devise_notification) { |*_args| true }
  end

  before do
    create(:team, :change_user_team, created_by: user)
    sign_in user
  end

  context 'when the addon is disabled via AddonSetting' do
    before { AddonSetting.create!(name: 'project_insights', enabled: false, configuration: {}) }

    it 'returns 403 for the insights endpoint' do
      get '/insights', params: { kind: 'status' }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
