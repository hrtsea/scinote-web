# frozen_string_literal: true

# 测试表征逾期豁免（eln_ui_service_strike_waivers · REQ-RES-TEST-STRIKE-3）
#
# 一句话语义：**放行一次提交，不消解占用**。spec V1.21 L1035「豁免不改变未回填
# 事实本身」「豁免后该人员仍未回填，则其占用继续累计，豁免不得用于无限规避」。
# 所以这里只记录「谁被放行过一次、谁放的、为什么、什么时候用掉」，
# 判定逻辑一律在 ServiceStrikeBook，不在这里重复算。
#
# ⚠ 与 eln_ui 其他 model 同源铁律：表名显式 self.table_name；类体裹 module Scinote::ElnUi。
module Scinote
  module ElnUi
    class ServiceStrikeWaiver < ActiveRecord::Base
      self.table_name = 'eln_ui_service_strike_waivers'

      belongs_to :user,       class_name: '::User', inverse_of: false
      belongs_to :granted_by, class_name: '::User', inverse_of: false

      scope :unused, -> { where(used_at: nil) }

      def unused?
        used_at.nil?
      end

      # 用掉这一次豁免（提交动作发生时才调，不是管理员点「豁免」时就调 ——
      # 提前调会让人拿着没用掉的额度反复试）。
      # ⚠ granted_by / reason 在**发放**那一刻就落库（谁放的、为什么），
      #   这里只补 used_at —— 让「放行人和原因」与「什么时候用掉」各自有归属，
      #   别在消费时硬塞一个「当前提交人」当豁免人。
      def consume!
        update!(used_at: Time.current)
      end
    end
  end
end
