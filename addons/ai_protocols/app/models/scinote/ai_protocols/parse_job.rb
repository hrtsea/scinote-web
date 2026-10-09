# frozen_string_literal: true

# AI 协议解析作业台账 —— 每日配额的真源 + 异步解析任务状态机。
#
# 官方语义：每用户每天最多 5 个 Import with AI 作业（BETA 限制）。
# 本表同时承载官方「异步三段式」的任务状态：
#   create (POST /parsed_protocols) -> status='processing'（不计配额）
#   show   (GET  /parsed_protocols/:id) 首轮若仍 processing -> 跑生成器 -> status='done',parsed_valid=true
#   import (POST /parsed_protocols/:id/import) -> 落库为协议
#
# ⚠ 配额只数「成功完成」(status='done') 的作业，processing 中的不计入；
#   失败 (status='error'/'rejected') 也不计入 —— 与官方「失败不该罚用户」一致。
#
# ⚠ 不做 belongs_to 关联到原生表：只按 user_id / created_at 查，避免与宿主模型耦合。
module Scinote
  module AiProtocols
    class ParseJob < ActiveRecord::Base
      self.table_name = 'ai_parse_jobs'

      STATUSES = %w[processing done rejected error].freeze
      DAILY_LIMIT = 5

      scope :today, -> { where(created_at: Time.current.utc.beginning_of_day..Time.current.utc.end_of_day) }
      scope :completed_today, ->(user) { today.where(user_id: user.id, status: 'done') }

      # 当日已成功完成次数（配额口径）。
      def self.used_today(user)
        return 0 if user.nil?

        completed_today(user).count
      end

      # 今日剩余可用次数。
      def self.remaining_for(user)
        [DAILY_LIMIT - used_today(user), 0].max
      end

      # 给前端弹窗用的配额快照（legacy 接口兼容）。
      def self.quota_for(user)
        used = used_today(user)
        { used: used, limit: DAILY_LIMIT, remaining: [DAILY_LIMIT - used, 0].max }
      end

      def self.quota_available?(user)
        used_today(user) < DAILY_LIMIT
      end

      # 创建一条 processing 任务（不计配额，成功后由 complete! 计入）。
      def self.create_processing!(user:, team: nil, mode: 'prompt_only', prompt: '', source_text: '')
        create!(
          user_id: user && user.id,
          team_id: team && team.id,
          mode: mode.to_s,
          prompt: prompt.to_s,
          source_text: source_text.to_s,
          status: 'processing'
        )
      end

      def processing?
        status == 'processing'
      end

      # 生成器产出 { protocol_params:, steps_params_json: } -> 落库为 done。
      def complete!(generated)
        protocol_params = generated[:protocol_params]
        steps = JSON.parse(generated[:steps_params_json].to_s.presence || '[]')
        data = {
          name: protocol_params[:name].to_s,
          description: protocol_params[:description].to_s,
          steps: steps.map do |s|
            {
              name: s['name'].to_s,
              description: s['description'].to_s,
              tables: Array(s['tables_attributes']).map do |t|
                { name: t['name'].to_s, data: JSON.parse(t['contents'].to_s.presence || '[]') }
              end
            }
          end
        }
        update!(
          status: 'done',
          parsed_valid: true,
          parsed_data: data.to_json
        )
      end

      def fail!(message)
        update!(status: 'error', last_error: message.to_s)
      end

      # parsed_data 反序列化为 Hash（nil 时返回 {}）。
      def parsed_data_hash
        return {} if read_attribute(:parsed_data).blank?

        JSON.parse(read_attribute(:parsed_data))
      rescue JSON::ParserError
        {}
      end
    end
  end
end
