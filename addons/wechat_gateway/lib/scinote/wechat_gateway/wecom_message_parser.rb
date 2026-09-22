require 'nokogiri'

module Scinote
  module WechatGateway
    # 解析「已解密的」企微回调 XML（即 WecomCrypto.decrypt_callback 的返回值）为统一 Message。
    # 用 Nokogiri 解析（主应用已依赖，稳健处理含 / + = 的 CDATA 与任意消息体）。
    module WecomMessageParser
      MSG_TYPE_MAP = {
        'text' => :text, 'image' => :image, 'voice' => :voice,
        'video' => :video, 'shortvideo' => :video, 'file' => :file,
        'location' => :location, 'event' => :event
      }.freeze

      # xml(String) -> Message
      def self.parse(xml)
        doc = Nokogiri::XML(xml)
        msg_type = (text(doc, 'MsgType') || 'text')
        type = MSG_TYPE_MAP[msg_type] || :text
        from = text(doc, 'FromUserName')
        content = text(doc, 'Content')
        media_id = text(doc, 'MediaId')
        pic_url = text(doc, 'PicUrl')
        ts = text(doc, 'CreateTime')

        media = []
        if media_id
          desc = { kind: type, media_id: media_id }
          desc[:url] = pic_url if pic_url && !pic_url.empty?
          media << desc
        end

        text_out = content
        if type == :event
          event = text(doc, 'Event')
          event_key = text(doc, 'EventKey')
          text_out = [event, event_key].compact.join(':')
        end

        Message.new(
          user_id: from,
          text: text_out || '',
          media: media,
          type: type,
          platform: :wecom,
          raw: xml,
          timestamp: ts ? ts.to_i : nil
        )
      end

      def self.text(doc, tag)
        el = doc.at_xpath("//#{tag}")
        el&.text
      end
    end
  end
end
