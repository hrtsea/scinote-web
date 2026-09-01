# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::Esignatures::ExportProof do
  let(:signer) { create(:user) }
  let(:signable) { create(:experiment) }

  it 'produces a proof containing the signatures and a VALID status' do
    Scinote::Esignatures::SignatureService.call(record: signable, user: signer, meaning: 'approve')
    out = StringIO.new
    output = described_class.call(signable, io: out)
    expect(output).to include('Electronic Signature Proof')
    expect(output).to include(signer.email)
    expect(output).to include('STATUS: VALID')
    expect(out.string).to include('STATUS: VALID')
  end

  it 'reports INVALID when the chain is broken' do
    rec = Scinote::Esignatures::SignatureService.call(record: signable, user: signer, meaning: 'x')
    # Deliberately bypasses the append-only model to simulate tampering.
    rec.update_columns(signature_hash: '0' * 64) # rubocop:disable Rails/SkipsModelValidations
    output = described_class.call(signable, io: nil)
    expect(output).to include('STATUS: INVALID')
  end
end
