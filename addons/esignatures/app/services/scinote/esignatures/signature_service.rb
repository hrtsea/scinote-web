# frozen_string_literal: true

require 'digest'

module Scinote
  module Esignatures
    # Creates an immutable, hash-chained signature record for any signable object
    # (Protocol / Result / Experiment / ...). Never mutates the signed record.
    class SignatureService
      class Error < StandardError; end

      def self.call(record:, user:, meaning:)
        new(record: record, user: user, meaning: meaning).call
      end

      def initialize(record:, user:, meaning:)
        @record = record
        @user = user
        @meaning = meaning
      end

      def self.record_hash_for(user:, record:, meaning:)
        Digest::SHA256.hexdigest(
          [user.id, record.class.name, record.id, record.updated_at&.iso8601, meaning].join('|')
        )
      end

      def call
        raise Error, 'signature meaning/intent is required' if meaning.blank?

        previous = Scinote::Esignatures::ESignatureRecord
                   .where(signable: @record)
                   .order(created_at: :desc, id: :desc)
                   .first
        previous_hash = previous&.signature_hash || '0'

        record_hash = self.class.record_hash_for(user: @user, record: @record, meaning: @meaning)
        signature_hash = Digest::SHA256.hexdigest(previous_hash + record_hash)

        Scinote::Esignatures::ESignatureRecord.create!(
          user: @user,
          signable: @record,
          meaning: @meaning,
          record_hash: record_hash,
          signature_hash: signature_hash,
          previous_hash: previous_hash,
          signed_at: Time.now.utc
        )
      end

      private

      attr_reader :record, :user, :meaning

      def record_fingerprint
        [
          user.id,
          record.class.name,
          record.id,
          record.updated_at&.iso8601,
          meaning
        ].join('|')
      end
    end
  end
end
