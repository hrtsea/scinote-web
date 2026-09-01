# frozen_string_literal: true

module Scinote
  module Esignatures
    # Per-team signature policy (e.g. whether a meaning/intent statement is required).
    class ESignature < ::ApplicationRecord
      self.table_name = 'e_signatures'
      belongs_to :team
    end
  end
end
