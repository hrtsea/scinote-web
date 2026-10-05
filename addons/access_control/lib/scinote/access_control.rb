# frozen_string_literal: true

require 'scinote/access_control/version'
require 'scinote/access_control/engine'

module Scinote
  module AccessControl
    class << self
        # 全局开关：false 时钩子跳过（create_engine HARD-GATE #4 兼容原则）
        def enabled?
          return @enabled unless @enabled.nil?
          addon_setting = AddonSetting.find_by(name: 'access_control') rescue nil
          @enabled = addon_setting.nil? ? true : addon_setting.enabled
        end

        def enabled=(value)
          @enabled = value
        end
      end
  end
end