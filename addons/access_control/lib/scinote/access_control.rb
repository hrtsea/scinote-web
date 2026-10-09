# frozen_string_literal: true

require 'scinote/access_control/version'

module Scinote
  module AccessControl
    class << self
      def enabled?
        return @enabled unless @enabled.nil?

        setting = addon_setting
        @enabled = setting ? setting.enabled : true
      end

      def enabled=(value)
        @enabled = value
      end

      # 启动自检。分两半，因为两半的外部依赖不同：
      #
      #   · 表存在性  —— 需要数据库连接。构建期（Dockerfile 的 CI 门禁）没有 db 容器，
      #     那条 DATABASE_URL 是占位符（`db` 解析到容器网段的地址 + 无密码），
      #     此时用 SKIP_ACCESS_CONTROL_DB_CHECK=1 跳过；**静态那半仍照跑**。
      #   · 装饰器挂载 —— 纯内存方法探测，任何时候都能查。
      #
      # 「列在不在 / 装饰挂没挂」原来散在运行时各处（十来处 respond_to? 探测），
      # 那是个坏交易：守卫的理由都成立（生产库跑不了 db:migrate、角色可能没部署），
      # 但代价是**每次调用都付一次探测**，而且失败是静默的——PI 点了放行只看到
      # 「失败」，永远不知道是开关关了、角色没了、还是 respond_to? 返回了 false。
      #
      # 这里收成一次：engine 的 to_prepare 末尾调一次，不满足直接炸，
      # 于是运行时那些探测能全部删掉，代码回到直路。
      # 本 addon 的迁移在这个实例上跑不通（db:migrate 被 ai_eln 的 down 迁移卡住），
      # 生产库历来是「照 _db/migrate_addon.rb 手工 load」。
      # 表名 → 迁移文件名的对照就写在这里，加表只改这一处。
      REQUIRED_TABLES = {
        'access_control_manual_grants' =>
          '20261005203000_create_access_control_manual_grants.rb',
        # OPEN-11：策略真源已从原生 projects 列搬到这张自有表
        'access_control_project_strategies' =>
          '20261005210000_create_access_control_project_strategies.rb'
      }.freeze

      def verify!
        verify_tables! unless ENV['SKIP_ACCESS_CONTROL_DB_CHECK'].present?

        return if Experiment.method_defined?(:ac_manually_granted?) ||
                  Experiment.private_method_defined?(:ac_manually_granted?)

        raise 'access_control addon: visibility grant decorator did not load — ' \
              'check app/decorators/scinote/access_control/*.'
      end

      private

        # 表存在性检查（ADR-0033 用来防「隔离引擎静默失效」的那道运行时护栏）。
        # 独立成方法是为了让构建期能只跳过它——静态那半（装饰器探测）必须继续跑，
        # 否则这道门禁就只剩个名字了。见 verify! 的注释。
        def verify_tables!
          conn = ActiveRecord::Base.connection

          REQUIRED_TABLES.each do |table, migration|
            next if conn.table_exists?(table)

            raise "access_control addon: #{table} table is missing — " \
                  "run addons/access_control/db/migrate/#{migration} " \
                  '(生产库用 _db/migrate_addon.rb 手工跑) before booting this addon.'
          end
        end

        # DB 还没起来的早期阶段 table_exists? 返回 false，之后每次调用重查——
        # 不会像 memo 那样把「这次查不到」锁死成永久 true。
        def addon_setting
          return @addon_setting if defined?(@addon_setting)

          @addon_setting = AddonSetting.table_exists? ? AddonSetting.find_by(name: 'access_control') : nil
        end
    end
  end
end
