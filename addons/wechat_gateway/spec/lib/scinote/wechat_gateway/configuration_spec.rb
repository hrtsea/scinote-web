# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module WechatGateway
    RSpec.describe Scinote::WechatGateway do
      after { described_class.configuration = nil }

      it 'defaults enabled to true' do
        described_class.configuration = nil
        expect(described_class.enabled?).to be true
      end

      it 'configure block sets credentials and switch' do
        described_class.configuration = nil
        described_class.configure do |c|
          c.enabled = false
          c.wecom_token = 'tok'
          c.wecom_corpid = 'wwabc'
          c.wecom_encoding_aes_key = 'A' * 43
        end
        expect(described_class.enabled?).to be false
        cfg = described_class.configuration
        expect(cfg.wecom_token).to eq('tok')
        expect(cfg.wecom_corpid).to eq('wwabc')
      end

      it 'enabled reflects boolean' do
        described_class.configuration = nil
        described_class.configuration.enabled = false
        expect(described_class.enabled?).to be false
        described_class.configuration.enabled = true
        expect(described_class.enabled?).to be true
      end
    end
  end
end
