# frozen_string_literal: true

require 'scinote/addon_settings/version'
require 'scinote/addon_settings/engine'

module Scinote
  module AddonSettings
    # 设置页卡片简介（参照 Label printers 的标题+描述风格）。
    def self.description
      'users.settings.account.addons.description'
    end

    # 配置子页的详细说明。
    def self.detailed_help
      'users.settings.account.addons.detailed_help'
    end
  end
end
