# frozen_string_literal: true

require 'scinote/wechat_gateway/wecom_reply'

module Scinote
  module WechatGateway
    RSpec.describe WecomReply do
      it '构造被动回复 XML 并互换收发方' do
        xml = described_class.text('user_wx', 'corp_id', 'hello')
        expect(xml).to include('<ToUserName><![CDATA[user_wx]]></ToUserName>')
        expect(xml).to include('<FromUserName><![CDATA[corp_id]]></FromUserName>')
        expect(xml).to include('<MsgType><![CDATA[text]]></MsgType>')
        expect(xml).to include('<Content><![CDATA[hello]]></Content>')
        expect(xml).to match(/<CreateTime>\d+<\/CreateTime>/)
      end

      it '转义 XML 特殊字符' do
        xml = described_class.text('u', 'f', 'a < b & c > d')
        expect(xml).to include('a &lt; b &amp; c &gt; d')
        expect(xml).not_to include('a < b')
      end

      it '超长内容被截断并提示' do
        long = 'x' * 5000
        out = described_class.truncate(long)
        expect(out.bytesize).to be <= described_class::MAX_CONTENT_BYTES + 100
        expect(out).to match(/已截断/)
      end

      it '短内容不被截断' do
        expect(described_class.truncate('短内容')).to eq('短内容')
      end
    end
  end
end
