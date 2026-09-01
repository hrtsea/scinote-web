module Scinote
  module I18n
    VERSION =
      File.read(
        File.join(File.dirname(__FILE__), '..', '..', '..', 'VERSION')
      ).strip.freeze
  end
end
