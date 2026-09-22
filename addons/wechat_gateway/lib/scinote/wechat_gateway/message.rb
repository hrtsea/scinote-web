module Scinote
  module WechatGateway
    # 统一消息结构：两个通道（iLink / 企微）归一后交给 intake。
    # media 为数组，每个元素为媒体描述符 hash：
    #   { kind: :image|:voice|:file|:video, aes_key:, url:, full_url:, file_name:, text: }
    # 文本消息 media 为空，type=:text。
    Message = Struct.new(
      :user_id, :text, :media, :type, :platform, :raw, :timestamp,
      keyword_init: true
    ) do
      def media
        self[:media] ||= []
      end
    end
  end
end
