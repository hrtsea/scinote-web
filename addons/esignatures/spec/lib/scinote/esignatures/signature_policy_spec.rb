# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::Esignatures::SignaturePolicy do
  let(:user) { create(:user) }

  it 'permits signing when the core manage permission allows it' do
    policy = described_class.new(user, build_stubbed(:experiment))
    allow(policy).to receive(:can_manage_experiment?).and_return(true)
    expect(policy.permits?).to be true
  end

  it 'forbids signing when the core manage permission denies it' do
    policy = described_class.new(user, build_stubbed(:experiment))
    allow(policy).to receive(:can_manage_experiment?).and_return(false)
    expect(policy.permits?).to be false
  end

  it 'dispatches to the protocol signing permission' do
    policy = described_class.new(user, build(:protocol))
    allow(policy).to receive(:can_manage_protocol_in_repository?).and_return(true)
    allow(policy).to receive(:can_manage_protocol_in_module?).and_return(false)
    expect(policy.permits?).to be true
  end

  it 'dispatches to the result signing permission' do
    policy = described_class.new(user, build(:result))
    allow(policy).to receive(:can_manage_result?).and_return(true)
    expect(policy.permits?).to be true
  end

  it 'forbids an unsupported record type' do
    expect(described_class.new(user, build_stubbed(:user)).permits?).to be false
  end

  it 'forbids when user or record is nil' do
    expect(described_class.new(nil, build_stubbed(:experiment)).permits?).to be false
    expect(described_class.new(user, nil).permits?).to be false
  end

  # Guard: canaid only loads addon permission files found via an engine's
  # `eager_load_paths` (see lib/scinote/esignatures/engine.rb). If that wiring
  # breaks, `permits?` would raise instead of silently degrading — but only when
  # someone actually tries to sign. These assertions fail the build immediately.
  describe 'canaid registration' do
    %w(sign_protocol_record sign_result_record sign_experiment_record).each do |permission|
      it "registers #{permission}" do
        expect(Canaid::PermissionsHolder.instance.has_permission?(permission)).to be true
      end
    end
  end
end
