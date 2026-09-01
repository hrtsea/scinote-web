# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::Esignatures::ChainVerifier do
  let(:signer) { create(:user) }
  let(:signable) { create(:experiment) }

  def sign(meaning)
    Scinote::Esignatures::SignatureService.call(record: signable, user: signer, meaning: meaning)
  end

  it 'reports valid for an intact chain' do
    sign('first')
    sign('second')
    report = described_class.verify(signable)
    expect(report[:valid]).to be true
    expect(report[:broken_at_id]).to be_nil
  end

  it 'reports valid for a record with no signatures' do
    expect(described_class.verify(signable)[:valid]).to be true
  end

  it 'detects a broken chain when a signature_hash is tampered' do
    first = sign('first')
    sign('second')
    # Deliberately bypasses the append-only model to simulate tampering.
    first.update_columns(signature_hash: 'deadbeef' * 8) # rubocop:disable Rails/SkipsModelValidations
    report = described_class.verify(signable)
    expect(report[:valid]).to be false
    expect(report[:broken_at_id]).to eq first.id
  end

  it 'flags record_modified when the signed record changed since signing' do
    sign('first')
    signable.update_columns(updated_at: Time.now.utc + 1.day) # rubocop:disable Rails/SkipsModelValidations
    report = described_class.verify(signable)
    expect(report[:valid]).to be true
    expect(report[:record_modified]).to be true
  end
end
