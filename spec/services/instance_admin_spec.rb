# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceAdmin do
  let(:default_admin) { double('user', id: 1) }
  let(:other_user) { double('user', id: 999) }

  around do |example|
    original = ApplicationSettings.instance.values['instance_admin_user_ids']
    example.run
    if original.nil?
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.except('instance_admin_user_ids')
      )
    else
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.merge('instance_admin_user_ids' => original)
      )
    end
  end

  describe '.admin?' do
    it 'returns true for the default admin (user id 1)' do
      expect(described_class.admin?(default_admin)).to be true
    end

    it 'returns false for other users by default' do
      expect(described_class.admin?(other_user)).to be false
    end

    it 'returns false for nil' do
      expect(described_class.admin?(nil)).to be false
    end

    it 'honors a configured admin list' do
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.merge('instance_admin_user_ids' => [999])
      )
      expect(described_class.admin?(other_user)).to be true
      expect(described_class.admin?(default_admin)).to be false
    end
  end

  describe '.admin_ids' do
    it 'falls back to the default when the setting is absent' do
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.except('instance_admin_user_ids')
      )
      expect(described_class.admin_ids).to eq([1])
    end
  end
end
