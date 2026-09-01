# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module Esignatures
    RSpec.describe SignatureService do
      let(:user) { create(:user) }
      # A real persisted AR object is required because the service queries
      # `where(signable: record)`, which relies on ActiveRecord's interface.
      let(:signable) { create(:user) }

      it 'creates an immutable signature record with a hash chain starting at 0' do
        record = described_class.call(record: signable, user: user, meaning: 'I approve')

        expect(record).to be_persisted
        expect(record.record_hash).to be_present
        expect(record.signature_hash).to be_present
        expect(record.previous_hash).to eq '0'
        expect(record.signable_type).to eq 'User'
        expect(record.signable_id).to eq signable.id
        expect(record.user).to eq user
      end

      it 'raises when meaning/intent is blank' do
        expect do
          described_class.call(record: signable, user: user, meaning: '')
        end.to raise_error(Scinote::Esignatures::SignatureService::Error)
      end

      it 'chains subsequent signatures to the previous signature hash' do
        first = described_class.call(record: signable, user: user, meaning: 'first')
        second = described_class.call(record: signable, user: user, meaning: 'second')

        expect(second.previous_hash).to eq first.signature_hash
        expect(second.signature_hash).not_to eq first.signature_hash
      end
    end
  end
end
