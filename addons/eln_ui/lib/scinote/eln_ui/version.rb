# frozen_string_literal: true

module Scinote
  module ElnUi
    VERSION = File.read(
      "#{File.dirname(__FILE__)}/../../../VERSION"
    ).strip.freeze
  end
end
