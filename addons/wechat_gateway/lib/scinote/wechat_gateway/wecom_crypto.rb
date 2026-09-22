require 'openssl'
require 'securerandom'
require 'digest'
require 'base64'

module Scinote
  module WechatGateway
    # 企微回调验签 + AES-256-CBC 解密（技术要点见计划 §9.2）
    #
    # 纯 Ruby，不依赖 Rails：核心方法 encrypt/decrypt/verify_signature 接收显式参数，
    # 可脱离 SciNote 单测（见 test/wecom_crypto_test.rb）。Rails 封装方法读 self.config。
    module WecomCrypto
      BLOCK_SIZE = 32 # 企微 PKCS7 用 32 字节块（AES 块为 16，但微信实现用 32）

      class << self
        # 由 engine.rb 的 config initializer 填充：
        #   {:token=>, :encoding_aes_key=>, :receive_id=>}（receive_id = 企微 corpid）
        attr_accessor :config
      end
      self.config = {}

      # ---- 纯方法（可单测）----

      # plaintext(String) + receive_id(String) + EncodingAESKey(43字符) -> base64 密文
      def self.encrypt(plaintext, receive_id, encoding_aes_key)
        key = aes_key(encoding_aes_key)
        msg_bin = plaintext.encode('UTF-8').bytes.pack('C*')  # BINARY
        rid_bin = receive_id.to_s.encode('UTF-8').bytes.pack('C*')
        plain = SecureRandom.random_bytes(16) +
                [msg_bin.bytesize].pack('N') +
                msg_bin +
                rid_bin
        cipher = OpenSSL::Cipher.new('AES-256-CBC')
        cipher.encrypt
        cipher.key = key
        cipher.iv = key[0, 16]
        enc = cipher.update(pkcs7_pad(plain)) + cipher.final
        Base64.strict_encode64(enc)
      end

      # base64 密文 + EncodingAESKey + 可选 receive_id 校验 -> 解密出的消息原文(String)
      def self.decrypt(base64_cipher, encoding_aes_key, receive_id = nil)
        key = aes_key(encoding_aes_key)
        cipher = OpenSSL::Cipher.new('AES-256-CBC')
        cipher.decrypt
        cipher.key = key
        cipher.iv = key[0, 16]
        padded = cipher.update(Base64.decode64(base64_cipher)) + cipher.final
        plain = pkcs7_unpad(padded)
        msg_len = plain[16, 4].unpack('N').first
        msg = plain[20, msg_len]
        rid = plain[20 + msg_len..]
        if receive_id && rid != receive_id
          raise "receive_id mismatch: got #{rid.inspect}, expect #{receive_id}"
        end
        msg.force_encoding('UTF-8')
      end

      # 企微签名：sha1(排序后拼接 [token, timestamp, nonce, encrypt])
      def self.verify_signature(token, timestamp, nonce, encrypt, signature)
        expected = Digest::SHA1.hexdigest([token, timestamp, nonce, encrypt].sort.join)
        expected == signature
      end

      # ---- Rails 回调封装（读 self.config）----

      # GET 校验 URL：解密 echostr 原样返回
      def self.verify_url(params)
        decrypt(params[:echostr].to_s, config[:encoding_aes_key], config[:receive_id])
      end

      # POST 收消息：验签 + 解密 XML 中的 <Encrypt>
      def self.decrypt_callback(xml_body, params)
        encrypt = extract_encrypt(xml_body)
        unless verify_signature(config[:token], params[:timestamp], params[:nonce],
                                 encrypt, params[:msg_signature])
          raise 'bad msg_signature'
        end
        decrypt(encrypt, config[:encoding_aes_key], config[:receive_id])
      end

      # ---- 内部辅助 ----

      def self.aes_key(encoding_aes_key)
        Base64.decode64(encoding_aes_key.to_s + '=') # 43字符 -> 补 '=' 成 44 -> 32字节
      end

      def self.pkcs7_pad(data, block_size = BLOCK_SIZE)
        pad = block_size - (data.bytesize % block_size)
        pad = block_size if pad.zero?
        data + pad.chr * pad
      end

      def self.pkcs7_unpad(data)
        pad = data[-1].ord
        raise 'bad pkcs7' if pad <= 0 || pad > BLOCK_SIZE
        data[0, data.bytesize - pad]
      end

      def self.extract_encrypt(xml)
        # 用字符串索引提取 <Encrypt> 的 CDATA，不依赖任何 XML 解析器。
        # 原因：REXML / Nokogiri 在本环境对「含 / + = 的 base64」CDATA 解析异常
        # （误报 Malformed/CData not finished），会直接导致真实企微回调解密失败。
        # 此处专门定位 <Encrypt><![CDATA[ 之后到首个 ]]> 的内容（Encrypt 的 CDATA
        # 不含 ']]>'，故安全）；注意必须锚定 <Encrypt> 而非首个 <![CDATA[，
        # 否则会误取到 ToUserName 等前置节点的内容。
        s = xml.to_s
        tag = '<Encrypt><![CDATA['
        open = s.index(tag)
        raise 'missing <Encrypt>' unless open
        close = s.index(']]>', open + tag.length)
        raise 'missing <Encrypt>' unless close
        s[open + tag.length, close - open - tag.length]
      end
    end
  end
end
