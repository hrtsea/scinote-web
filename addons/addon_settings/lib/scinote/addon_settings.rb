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

    # 该 addon 提供附加组件管理界面本身，必须常驻启用，不可被切换。
    def self.toggleable?
      false
    end
  end
end
