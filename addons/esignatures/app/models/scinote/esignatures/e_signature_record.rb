# frozen_string_literal: true

module Scinote
  module Esignatures
    # An immutable, append-only electronic signature event bound to a record.
    # No update/delete paths are provided on purpose (21 CFR Part 11).
    class ESignatureRecord < ::ApplicationRecord
      self.table_name = 'e_signature_records'
      belongs_to :user
      belongs_to :signable, polymorphic: true

      validates :meaning, :record_hash, :signature_hash, :previous_hash, :signed_at,
                presence: true
    end
  end
end
