module Scinote
  module WechatGateway
    # 统一消息结构：两个通道（iLink / 企微）归一后交给 intake。
    # media 为数组，每个元素为媒体描述符 hash：
    #   { kind: :image|:voice|:file|:video, aes_key:, url:, full_url:, file_name:, text: }
    # 文本消息 media 为空，type=:text。
    # chat_id：群会话 ID（企微群 ChatId）；mentions：被 @ 的微信 userid 列表（群场景）。
    # to_user：消息接收方（企微被动回包时作为回复的 FromUserName，即 bot/corpid）。
    Message = Struct.new(
      :user_id, :text, :media, :type, :platform, :raw, :timestamp,
      :chat_id, :mentions, :to_user,
      keyword_init: true
    ) do
      def media
        self[:media] ||= []
      end

      def mentions
        self[:mentions] ||= []
      end
    end
  end
end
