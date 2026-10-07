# frozen_string_literal: true

# ELN UI —— 项目归档导出（报告 §5 第 6 项 #10 · spec SCN-PM-ARCH-1/2/3）
#
# 规格要求「归档包预览 / 一键导出 ZIP」。ZIP 需聚合多类型文件，最小可验证实现是
# 把项目结构化数据（基础信息 / 指标 / 花费 / 实验 / 文档）导出为一份 CSV 预览包。
# 不碰原生归档状态机（archived 由原生端点维护），只聚合已有真相数据。
require 'csv'

module Scinote
  module ElnUi
    class ProjectArchiveExport
      def self.call(project)
        detail = Scinote::ElnUi::ProjectDetailPayload.call(project)
        csv = CSV.generate(headers: true, encoding: 'UTF-8') do |row|
          row << ['区块', '字段', '值']
          detail[:projectBasic].each { |k, v| row << ['项目基础', k.to_s, v.to_s] }
          detail[:projectMetrics].each do |m|
            row << ['指标', m[:name], "目标=#{m[:target]} 当前=#{m[:current]} 达标=#{m[:ok]}"]
          end
          detail[:projectCost][:rows].each { |r| row << ['花费', r[:category], "#{r[:amount]} (#{r[:share]})"] }
          detail[:experiments].each { |e| row << ['实验', e[:fullName], e[:status]] }
          detail[:requiredDocs].each { |d| row << ['必需文档', d[:name], "版本#{d[:ver]} 上传=#{d[:uploaded]}"] }
          detail[:otherDocs].each { |d| row << ['其他文档', d[:name], "#{d[:type]} by #{d[:by]}"] }
        end
        "\uFEFF#{csv}"
      end
    end
  end
end
