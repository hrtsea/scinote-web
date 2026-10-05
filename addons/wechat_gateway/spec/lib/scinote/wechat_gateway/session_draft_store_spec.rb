# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe SessionDraftStore do
      let(:store) { described_class.new }

      it '未绑定时 get 返回 nil' do
        expect(store.get(1)).to be_nil
      end

      it 'put 默认 body 为空、未锁定' do
        store.put(2, 3)
        expect(store.get(2)).to eq(exp_id: 3, body: '', locked: false)
      end

      it 'put/get/pop 生命周期' do
        store.put(1, 42, 'body')
        expect(store.get(1)).to eq(exp_id: 42, body: 'body', locked: false)
        expect(store.pop(1)).to eq(exp_id: 42, body: 'body', locked: false)
        expect(store.get(1)).to be_nil
      end

      it 'put 可显式锁定' do
        store.put(1, 42, 'body', locked: true)
        expect(store.locked?(1)).to be true
      end

      it 'locked? 对不存在的 key 返回 false' do
        expect(store.locked?(99)).to be false
      end

      it 'mark_locked 锁定当前草稿并返回 true' do
        store.put(1, 42, 'body')
        expect(store.mark_locked(1)).to be true
        expect(store.locked?(1)).to be true
      end

      it 'mark_locked 无草稿时返回 false' do
        expect(store.mark_locked(99)).to be false
      end

      it 'pop 对不存在的 key 返回 nil' do
        expect(store.pop(99)).to be_nil
      end
    end
  end
end
