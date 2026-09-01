# frozen_string_literal: true

require 'digest'

module Scinote
  module Esignatures
    # Verifies the append-only hash chain of ESignatureRecord for a signable.
    #
    # Each signature_hash must equal H(previous_hash + record_hash) and the first
    # record must be anchored to '0'. Recomputing record_hash from the *current*
    # signed record surfaces post-signing tampering (record_modified).
    #
    # Returns a hash: { valid:, record_modified:, broken_at_id:, error: }.
    class ChainVerifier
      ANCHOR = '0'

      def self.verify(signable)
        new(signable).verify
      end

      def initialize(signable)
        @signable = signable
      end

      def verify
        records = Scinote::Esignatures::ESignatureRecord
                  .where(signable: @signable)
                  .order(created_at: :asc, id: :asc)

        expected_prev = ANCHOR
        records.each do |rec|
          unless rec.previous_hash == expected_prev
            return invalid(broken_at_id: rec.id,
                           error: 'chain link broken: previous_hash does not chain')
          end

          expected = Digest::SHA256.hexdigest(rec.previous_hash + rec.record_hash)
          return invalid(broken_at_id: rec.id, error: 'signature_hash mismatch') unless rec.signature_hash == expected

          expected_prev = rec.signature_hash
        end

        modified = records.any? do |rec|
          next false if rec.signable.nil?

          rec.record_hash != SignatureService.record_hash_for(
            user: rec.user, record: rec.signable, meaning: rec.meaning
          )
        end

        { valid: true, record_modified: modified, broken_at_id: nil, error: nil }
      end

      private

      def invalid(broken_at_id:, error:)
        { valid: false, record_modified: nil, broken_at_id: broken_at_id, error: error }
      end
    end
  end
end
