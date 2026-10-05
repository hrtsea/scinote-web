module Scinote
  module WechatGateway
    # 用户级长期状态行（表 wechat_gateway_user_states）。
    # 主键 = scinote_user_id：同一用户在 iLink / 企业微信两个通道共享同一份状态，
    # 因此「默认项目」「待选项目」不会因为换通道而丢失或不一致。
    class UserState < ApplicationRecord
      self.table_name = 'wechat_gateway_user_states'
      self.primary_key = 'scinote_user_id'

      validates :scinote_user_id, presence: true

      # 取（无则建）用户状态行；并发下 RecordNotUnique 时回退查询。
      def self.for(user_id)
        find_or_create_by!(scinote_user_id: user_id.to_i)
      rescue ActiveRecord::RecordNotUnique
        find_by(scinote_user_id: user_id.to_i)
      end
    end
  end
end
