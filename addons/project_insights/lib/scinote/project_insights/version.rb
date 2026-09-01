# frozen_string_literal: true

module Scinote
  module ProjectInsights
    VERSION =
      File.read(
        File.join(File.dirname(__FILE__), '..', '..', '..', 'VERSION')
      ).strip.freeze
  end
end
