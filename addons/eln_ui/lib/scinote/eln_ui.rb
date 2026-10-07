# frozen_string_literal: true

require 'scinote/eln_ui/version'

module Scinote
  module ElnUi
    # 测试表征服务闸门的**可配置项**（REQ-RES-TEST-STRIKE）。
    #
    # spec V1.21 L1021：「阈值与宽限期均为**可配置项**，不得硬编码」；
    #            L1031「当管理员调整阈值或宽限期，则冻结判定按新配置**即时生效**」。
    #
    # ⚠ 所以下面两个 reader **一律不缓存** —— 缓存就等于把「即时生效」这句话废掉
    #   （管理员在设置页改完，代码还在用内存里那一份，直到进程重启）。
    #
    # 存储走宿主现成的 AddonSetting（addon_settings engine 提供，见
    # AddonSetting.config_schema_for / .typed_configuration），不另造一套配置表。
    DEFAULTS = {
      'service_result_grace_days' => 30,   # 宽限期：执行后多少天内必须回填结果，默认 30 天
      'service_result_strike_limit' => 10, # 冻结阈值：未消解占用达此数即冻结提交，默认 10
      # 🔴 REQ-RES-RECEIPT / ADR-0032：未验货申请达此数即冻结「新建材料申请」，默认 2。
      #   ⚠ 走**同一处**模块级配置而不是 per-project 表：服务逾期冻结与材料未验货冻结
      #     是一对**镜像**（SCN-RES-TEST-STRIKE-2 只冻服务 / SCN-RES-RECEIPT-4 只冻材料），
      #     两者合起来覆盖申请类型全集 —— 阈值若一个全局一个按项目，就是两套口径，
      #     「机制只有一份」当场破掉。
      'receipt_pending_block_limit' => 2
    }.freeze

    # 设置页据此动态渲染表单（AddonSetting.config_schema_for('eln_ui') 读的就是它）。
    def self.config_schema
      [
        { key: 'service_result_grace_days',  type: 'integer', default: 30,
          label: 'settings.eln_ui.service_result_grace_days',
          help:  'settings.eln_ui.service_result_grace_days_help' },
        { key: 'service_result_strike_limit', type: 'integer', default: 10,
          label: 'settings.eln_ui.service_result_strike_limit',
          help:  'settings.eln_ui.service_result_strike_limit_help' },
        { key: 'receipt_pending_block_limit', type: 'integer', default: 2,
          label: 'settings.eln_ui.receipt_pending_block_limit',
          help:  'settings.eln_ui.receipt_pending_block_limit_help' }
      ]
    end

    # 当前配置值（未配置过 → 返回 spec 给的默认值）。
    # ⚠ 每次都重新读：配置改完当次请求就要生效，见上面「不缓存」那条。
    def self.config
      stored = if defined?(::AddonSetting) && ::AddonSetting.table_exists?
                ::AddonSetting.find_by(name: 'eln_ui')&.configuration
              else
                {}
              end
      DEFAULTS.merge(stored || {})
    end

    # 执行单自批准起、多少天内必须回填结果文件（默认 30）
    def self.service_result_grace_days
      config['service_result_grace_days'].to_i
    end

    # 未消解占用达到多少就冻结该申请人提交新的测试表征申请（默认 10）
    def self.service_result_strike_limit
      config['service_result_strike_limit'].to_i
    end

    # 名下「已终审通过但累计已验 < 申请量」的申请达到多少，就冻结其新建材料申请（默认 2）
    # ⚠ 阈值 0 或负数一律当 1 处理：**0 会变成「有未验货单也放行」**，
    #   那是把闸门关掉而不是调松，属配置事故。
    def self.receipt_pending_block_limit
      n = config['receipt_pending_block_limit'].to_i
      n < 1 ? 1 : n
    end
  end
end
