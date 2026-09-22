require_relative 'message'
require_relative 'binding_resolver'
require_relative 'wecom_crypto'
require_relative 'wecom_message_parser'
require_relative 'ilink_message_parser'

module Scinote
  module WechatGateway
    # 统一消息入口：
    #   - `receive(platform, raw, params)` 高层入口：解密 + 解析 raw -> Message -> 解析身份 ->（已绑定）交 intake。
    #   - `dispatch(platform, message)` 仅做身份解析，返回 scinote_user_id 或 nil（契约：未绑定返回 nil，ilink_test 依赖）。
    #
    # 解析层（WecomCrypto / WecomMessageParser / IlinkMessageParser）均为纯 Ruby，可无实例单测（见 test/inbound_test.rb）。
    # intake 写入（F4/F5）由 ticket 06 落地，经可注入的 `intake_handler` 接入，默认 no-op。
    module Inbound
      BIND_GUIDANCE = '您尚未绑定 SciNote 账号。请打开 SciNote → 设置 → 微信绑定，' \
                      '生成一次性绑定码后发送「/bind <码>」完成绑定。'.freeze

      class << self
        attr_writer :store, :intake_handler

        def store
          @store ||= ActiveRecordBindingStore.new # 运行时由 Rails autoload 解析
        end

        # 注入的 intake 处理器：proc(user_id, message) -> 任意结果。ticket 06 落地后赋值。
        def intake_handler
          @intake_handler ||= ->(_user_id, _message) { nil }
        end

        # 统一入口（回调控制器 / 桥接调用）：原始 raw + params -> 解析身份并（已绑定）交 intake。
        # platform: :wecom | :ilink
        #   wecom: raw = 加密回调 XML 文本；params = {timestamp, nonce, msg_signature}
        #   ilink: raw = iLink payload Hash
        # 返回：
        #   已绑定 -> { bound: true, user_id:, message:, intake: <handler 结果> }
        #   未绑定 -> { bound: false, message:, guidance: BIND_GUIDANCE }
        def receive(platform, raw, params = {})
          message = parse(platform, raw, params)
          user_id = dispatch(platform, message)
          if user_id.nil?
            { bound: false, message: message, guidance: BIND_GUIDANCE }
          else
            { bound: true, user_id: user_id, message: message,
              intake: intake_handler.call(user_id, message) }
          end
        end

        # 解析原始 payload 为统一 Message（纯函数，可单测）。
        def parse(platform, raw, params = {})
          case platform
          when :wecom
            decrypted = WecomCrypto.decrypt_callback(raw.to_s, params)
            WecomMessageParser.parse(decrypted)
          when :ilink
            IlinkMessageParser.parse(raw)
          else
            raise "unknown platform: #{platform.inspect}"
          end
        end

        # 身份解析：已绑定返回 scinote_user_id（Integer），未绑定返回 nil。
        # 保持此返回契约不变（ticket 05 的 ilink_test.rb 断言未绑定时为 nil）。
        def dispatch(platform, message)
          BindingResolver.new(store).resolve(message.user_id, platform)
        end
      end
    end
  end
end
