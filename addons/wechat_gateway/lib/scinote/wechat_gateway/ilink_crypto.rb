require 'openssl'
require 'base64'

module Scinote
  module WechatGateway
    # iLink CDN 媒体 AES-128-ECB 解密（移植 wechatbot SDK crypto）。
    #
    # 注意：第三方 wechatbot SDK 未 vendored 到本仓库，以下按 WeChat CDN 媒体
    # 通用约定实现：aeskey 为 16 字节密钥的 base64；AES-128-ECB + PKCS7。
    # decode_aes_key 的确切推导（是否额外 md5）需真机/SDK 源码核对。
    module IlinkCrypto
      def self.decode_aes_key(aes_key)
        Base64.decode64(aes_key.to_s) # 期望得到 16 字节密钥
      end

      # ciphertext: 原始密文; key: 16 字节
      def self.aes128_ecb_decrypt(ciphertext, key)
        raise 'key 必须为 16 字节（AES-128）' unless key.bytesize == 16
        cipher = OpenSSL::Cipher.new('AES-128-ECB')
        cipher.decrypt
        cipher.key = key
        cipher.padding = 0 # 关闭 OpenSSL 自动去 pad，手动处理
        padded = cipher.update(ciphertext) + cipher.final
        unpad_pkcs7(padded)
      end

      # 便捷：直接吃 iLink 下发的 aeskey 字符串
      def self.decrypt_media(ciphertext, aes_key)
        aes128_ecb_decrypt(ciphertext, decode_aes_key(aes_key))
      end

      def self.unpad_pkcs7(data)
        pad = data[-1].ord
        raise 'bad pkcs7' if pad <= 0 || pad > 16
        data[0, data.bytesize - pad]
      end
    end
  end
end
