module Scinote
  module WechatGateway
    # 把 iLink 下发的消息 raw（Hash）归一为统一 Message。
    # 按 image_item / voice_item / file_item / text_item 子结构识别媒体类型，
    # 不依赖 SDK 的 MessageItemType 枚举值（更鲁棒）。
    module IlinkMessageParser
      # 从 *_item 中抽取 CDN 媒体字段（顶层或嵌套 media 子对象都兼容）
      def self.media_fields(h)
        m = h['media'] || {}
        {
          aes_key: h['aeskey'] || m['aeskey'],
          url: h['url'] || m['url'],
          full_url: h['full_url'] || m['full_url']
        }
      end

      # raw -> Message
      def self.parse(raw)
        items = raw['item_list'] || []
        text_parts = []
        media = []

        items.each do |it|
          if it['text_item']
            text_parts << (it.dig('text_item', 'text').to_s)
          elsif it['image_item']
            f = media_fields(it['image_item'])
            media << { kind: :image }.merge(f)
          elsif it['voice_item']
            vi = it['voice_item']
            f = media_fields(vi)
            media << { kind: :voice, text: vi['text'] }.merge(f)
          elsif it['file_item']
            fi = it['file_item']
            f = media_fields(fi)
            media << { kind: :file, file_name: fi['file_name'], len: fi['len'] }.merge(f)
          elsif it['video_item']
            f = media_fields(it['video_item'])
            media << { kind: :video }.merge(f)
          end
        end

        text = text_parts.reject(&:empty?).join("\n")
        type = if media.any? { |m| m[:kind] == :image }
                 :image
               elsif media.any? { |m| m[:kind] == :voice }
                 :voice
               elsif media.any? { |m| m[:kind] == :file }
                 :file
               elsif media.any? { |m| m[:kind] == :video }
                 :video
               else
                 :text
               end

        Message.new(
          user_id: resolve_user_id(raw),
          text: text,
          media: media,
          type: type,
          platform: :ilink,
          raw: raw,
          timestamp: raw['create_time_ms']
        )
      end

      # 群模式：ILINK_GROUP_FIELD 指向 raw 中的群 ID 字段时，user_id 变为 g.<room>.<sender>
      def self.resolve_user_id(raw)
        gf = ENV['ILINK_GROUP_FIELD']
        if gf && (gid = raw[gf])
          "g.#{gid}.#{raw['from_user_id']}"
        else
          raw['from_user_id'].to_s
        end
      end
    end
  end
end
