module Scinote
  module WechatGateway
    class WechatUserBinding < ApplicationRecord
      validates :wechat_id, :scinote_user_id, :platform, presence: true
      validates :wechat_id, uniqueness: { scope: :platform }

      scope :for, ->(wechat_id, platform) {
        where(wechat_id: wechat_id, platform: platform).where(status: 'active')
      }
    end
  end
end
