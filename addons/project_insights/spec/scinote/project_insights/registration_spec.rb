# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::ProjectInsights do
  describe '.enabled?' do
    it 'is true by default (no setting row => mounted addon on)' do
      expect(described_class.enabled?).to be true
    end

    it 'is false when the addon setting is disabled' do
      AddonSetting.create!(name: 'project_insights', enabled: false, configuration: {})
      expect(described_class.enabled?).to be false
    end

    it 'is true when the addon setting is explicitly enabled' do
      AddonSetting.create!(name: 'project_insights', enabled: true, configuration: {})
      expect(described_class.enabled?).to be true
    end
  end

  describe '.register_widgets!' do
    after do
      Extends::DEFAULT_DASHBOARD_CONFIGURATION
        .reject! { |w| w[:partial].to_s.start_with?('dashboards/insights_') }
    end

    it 'registers the 4 widgets when the addon is enabled' do
      AddonSetting.create!(name: 'project_insights', enabled: true, configuration: {})
      described_class.register_widgets!
      partials = Extends::DEFAULT_DASHBOARD_CONFIGURATION.pluck(:partial)
      expect(partials).to include(
        'dashboards/insights_status', 'dashboards/insights_workload',
        'dashboards/insights_bottlenecks', 'dashboards/insights_due_dates'
      )
    end

    it 'registers no widgets when the addon is disabled' do
      AddonSetting.create!(name: 'project_insights', enabled: false, configuration: {})
      described_class.register_widgets!
      partials = Extends::DEFAULT_DASHBOARD_CONFIGURATION.pluck(:partial)
      expect(partials).not_to include('dashboards/insights_status')
    end
  end
end
