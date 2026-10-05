# frozen_string_literal: true

module Scinote
  module ElnUi
    # 实验二开主数据（原生 table_name 显式写死，不依赖 engine 的 table_name_prefix 推断）
    #
    # 承载「原生没有承载面」的几格：业务编号 / 实验目的 / 实验方案与方法 / 显式负责人 / 来源。
    # 原生 experiments 表**不加任何列** —— 这是项目铁律「不动原生数据库」的落点，
    # 二开数据一律进 eln_ui_* 自有表，以 experiment_id 关联。
    #
    # 留白是合法状态：没填 purpose / method 时 payload 给空串，页面上就是空，
    # 而不是把原型里那套演示文案（Dow ADH-6066 / 拉伸剪切强度 ≥ 8.0 MPa / 张负责人）当真值渲染。
    class ExperimentProfile < ActiveRecord::Base
      self.table_name = 'eln_ui_experiment_profiles'

      # ⚠ class_name 带 :: 前缀：isolate_namespace 会把 :experiment 解析成
      #   Scinote::ElnUi::Experiment（不存在）→ 必须显式指到顶层原生模型。
      belongs_to :experiment, class_name: '::Experiment', inverse_of: false
      belongs_to :owner_user, class_name: '::User', optional: true

      # 幂等 upsert 用：一个实验只有一条档案（migration 里 experiment_id 唯一索引）
      def self.upsert_for!(experiment, attrs)
        find_or_initialize_by(experiment_id: experiment.id)
          .tap { |record| record.update!(attrs.merge(experiment: experiment)) }
      end
    end
  end
end
