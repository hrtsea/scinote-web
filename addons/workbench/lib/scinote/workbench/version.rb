# frozen_string_literal: true

module Scinote
  module Workbench
    VERSION = File.read(
      "#{File.dirname(__FILE__)}/../../../VERSION"
    ).strip.freeze
  end
end
