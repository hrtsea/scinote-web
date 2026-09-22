require 'securerandom'

module Scinote
  module WechatGateway
    # iLink 私聊 DM 桥接：长轮询收消息 → 解析为 Message → 交 Inbound 解析身份。
    #
    # 网络层（get_updates 长轮询）通过可注入 transport 解耦，便于无实例单测。
    # 真实 transport 须按 iLink 协议实现（不在本仓库，需 SDK/真机协议）；
    # 这里只实现「拿到 raw → 解析 → 分发」的确定逻辑。
    module IlinkBridge
      BOT_MESSAGE_TYPE = 2 # message_type==BOT：自身回包，跳过避免回环

      # 处理单条 raw；返回解析出的 Message 或 nil（被跳过）
      def self.process(raw, handler: Inbound)
        return nil if raw['message_type'] == BOT_MESSAGE_TYPE
        msg = IlinkMessageParser.parse(raw)
        handler.dispatch(:ilink, msg)
        msg
      end

      # 长轮询循环：poller.call 返回下一条 raw Hash，返回 nil 表示停止。
      def self.run(poller, handler: Inbound)
        loop do
          raw = poller.call
          break if raw.nil?
          process(raw, handler: handler)
        end
      end

      # 下载并解密一条媒体（AES-128-ECB）。http_get 为注入的 GET 客户端，
      # 接收 URL 返回 bytes；默认用 Ruby 内置 URI + Net::HTTP。
      def self.download_media(descriptor, http_get: method(:default_http_get))
        url = descriptor[:full_url] || descriptor[:url]
        raise 'media 无可用 URL' unless url
        ciphertext = http_get.call(url)
        IlinkCrypto.decrypt_media(ciphertext, descriptor[:aes_key])
      end

      def self.default_http_get(url)
        require 'uri'
        require 'net/http'
        uri = URI(url)
        Net::HTTP.get(uri)
      end
    end
  end
end
