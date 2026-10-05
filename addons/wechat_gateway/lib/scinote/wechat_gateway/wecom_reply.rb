# frozen_string_literal: true

module Scinote
  module WechatGateway
    # 企微被动回复（5 秒内同步回包）：把文本 reply 包成明文 XML。
    # 企微网关会对整个 HTTP body 再整体加密，故此处只需明文 XML。
    #
    # 被动回复的收发方需互换：
    #   ToUserName   = 原消息 FromUserName（即发送者微信 userid）
    #   FromUserName = 原消息 ToUserName（即 bot/corpid，见 WecomCrypto.config[:receive_id]）
    module WecomReply
      # to_user:  回复的接收方（用户微信 userid）
      # from_user: 回复的发送方（bot/corpid）
      # content:   文本正文（自动转义 XML 特殊字符）
      def self.text(to_user, from_user, content)
        ts = Time.now.to_i
        "<xml>" \
          "<ToUserName><![CDATA[#{esc(to_user)}]]></ToUserName>" \
          "<FromUserName><![CDATA[#{esc(from_user)}]]></FromUserName>" \
          "<CreateTime>#{ts}</CreateTime>" \
          "<MsgType><![CDATA[text]]></MsgType>" \
          "<Content><![CDATA[#{esc(content)}]]></Content>" \
          "</xml>"
      end

      # 文本超长（企微被动回复 Content 建议 < 2048 字节）时截断并提示。
      MAX_CONTENT_BYTES = 1800

      def self.truncate(content)
        return content if content.bytesize <= MAX_CONTENT_BYTES

        head = content.byteslice(0, MAX_CONTENT_BYTES)
        "#{head}…（内容过长，已截断，请到 SciNote Web 查看完整记录）"
      end

      def self.esc(str)
        str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
    end
  end
end
