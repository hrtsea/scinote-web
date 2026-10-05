# frozen_string_literal: true

module Scinote
  module WechatGateway
    # 把 AI 抽取的 StructuredRecord 落到 ai_eln 的 Formulation 一等实体（Ticket 06）。
    #
    # 硬约束（读 ai_eln 模型/迁移确认）：
    #   - Formulation: team + created_by + name 必填
    #   - FormulationComponent: 必须挂宿主 RepositoryRow（物料主数据）+ amount/unit 必填
    #   - FormulationProperty: measured_value 或 target_value 至少其一
    # 因此组件需 `material_resolver`（成分名 -> RepositoryRow）才能落库；无法匹配的成分跳过（不伪造）。
    # ai_eln 未加载（无 Formulation 常量）时整体 no-op 返回 nil，不阻塞原文落库。
    class FormulationWriter
      def initialize(material_resolver: nil)
        @material_resolver = material_resolver
      end

      # record -> Formulation | nil（失败返回 nil，不抛给录入链路）
      def write(record, team:, created_by:)
        return nil unless defined?(Scinote::AiEln::Formulation)

        formulation = Scinote::AiEln::Formulation.create!(
          team: team,
          created_by: created_by,
          name: record.experiment_title.presence || '微信录入配方',
          description: AiProcessor.format_body('', record)
        )
        write_components(formulation, record)
        write_properties(formulation, record)
        formulation
      rescue StandardError => e
        warn_log("formulation write failed: #{e.message}")
        nil
      end

      private

      def write_components(formulation, record)
        record.components.each do |c|
          if c.amount.nil? || c.unit.blank?
            warn_log("skip component #{c.name}: amount/unit missing")
            next
          end

          row = @material_resolver&.call(c.name)
          if row.nil?
            warn_log("skip component #{c.name}: no material match")
            next
          end

          Scinote::AiEln::FormulationComponent.create!(
            formulation: formulation, repository_row: row, amount: c.amount, unit: c.unit
          )
        end
      end

      def write_properties(formulation, record)
        record.results.each do |r|
          if r.value.nil?
            warn_log("skip property #{r.property}: value missing")
            next
          end

          Scinote::AiEln::FormulationProperty.create!(
            formulation: formulation, name: r.property,
            measured_value: r.value, measured_unit: r.unit
          )
        end
      end

      def warn_log(msg)
        Rails.logger.warn("[wechat_gateway] #{msg}") if defined?(Rails)
      end
    end
  end
end
