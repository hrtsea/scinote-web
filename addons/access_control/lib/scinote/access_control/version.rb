# frozen_string_literal: true

module Scinote
  module AccessControl
    VERSION = File.read(
      "#{File.dirname(__FILE__)}/../../../VERSION"
    ).strip.freeze
  end
end