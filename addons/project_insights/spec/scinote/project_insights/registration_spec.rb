# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::ProjectInsights do
  describe '.enabled?' do
    it 'ENV 未设置时为 false' do
      original = ENV.fetch('PROJECT_INSIGHTS_ENABLED', nil)
      ENV.delete('PROJECT_INSIGHTS_ENABLED')
      expect(described_class.enabled?).to be false
      ENV['PROJECT_INSIGHTS_ENABLED'] = original
    end

    it 'PROJECT_INSIGHTS_ENABLED=true 时为 true' do
      original = ENV.fetch('PROJECT_INSIGHTS_ENABLED', nil)
      ENV['PROJECT_INSIGHTS_ENABLED'] = 'true'
      expect(described_class.enabled?).to be true
      ENV['PROJECT_INSIGHTS_ENABLED'] = original
    end
  end

  describe '.register_widgets!' do
    after do
      Extends::DEFAULT_DASHBOARD_CONFIGURATION
        .reject! { |w| w[:partial].to_s.start_with?('dashboards/insights_') }
    end

    it '在 ENV 门控下注册 4 个 widget' do
      ENV['PROJECT_INSIGHTS_ENABLED'] = 'true'
      described_class.register_widgets!
      partials = Extends::DEFAULT_DASHBOARD_CONFIGURATION.pluck(:partial)
      expect(partials).to include(
        'dashboards/insights_status', 'dashboards/insights_workload',
        'dashboards/insights_bottlenecks', 'dashboards/insights_due_dates'
      )
    end

    it '未启用时不注册任何 widget' do
      ENV.delete('PROJECT_INSIGHTS_ENABLED')
      described_class.register_widgets!
      partials = Extends::DEFAULT_DASHBOARD_CONFIGURATION.pluck(:partial)
      expect(partials).not_to include('dashboards/insights_status')
    end
  end
end
