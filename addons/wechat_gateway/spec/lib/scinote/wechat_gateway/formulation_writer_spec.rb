# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe FormulationWriter do
      let(:team) { double('team') }
      let(:user) { double('user') }
      let(:row) { double('repository_row') }
      let(:resolver) { ->(name) { name == 'PP' ? row : nil } }
      let(:writer) { described_class.new(material_resolver: resolver) }

      let(:record) do
        AiProcessor::StructuredRecord.new(
          experiment_title: 'T',
          components: [
            AiProcessor::Component.new(name: 'PP', amount: 100, unit: 'g'),
            AiProcessor::Component.new(name: 'X', amount: 5, unit: 'g'),   # 无物料匹配 -> 跳过
            AiProcessor::Component.new(name: 'Y', amount: nil, unit: 'g')  # 缺 amount -> 跳过
          ],
          results: [
            AiProcessor::ResultItem.new(property: '冲击', value: 23.5, unit: 'kJ/m²'),
            AiProcessor::ResultItem.new(property: '空', value: nil, unit: 'MPa') # 缺值 -> 跳过
          ],
          process_params: {}, notes: ''
        )
      end

      before do
        stub_const('Scinote::AiEln', Module.new) unless defined?(Scinote::AiEln)
        stub_const('Scinote::AiEln::Formulation', Class.new)
        stub_const('Scinote::AiEln::FormulationComponent', Class.new)
        stub_const('Scinote::AiEln::FormulationProperty', Class.new)
      end

      it '创建 Formulation + 可匹配组件 + 有值性质，跳过不完整项' do
        formulation = double('formulation')
        expect(Scinote::AiEln::Formulation).to receive(:create!)
          .with(hash_including(team: team, created_by: user, name: 'T'))
          .and_return(formulation)
        expect(Scinote::AiEln::FormulationComponent).to receive(:create!)
          .once.with(formulation: formulation, repository_row: row, amount: 100, unit: 'g')
        expect(Scinote::AiEln::FormulationProperty).to receive(:create!)
          .once.with(formulation: formulation, name: '冲击', measured_value: 23.5, measured_unit: 'kJ/m²')

        expect(writer.write(record, team: team, created_by: user)).to be(formulation)
      end

      it 'ai_eln 未加载时 no-op 返回 nil' do
        hide_const('Scinote::AiEln::Formulation')
        expect(writer.write(record, team: team, created_by: user)).to be_nil
      end

      it '落库异常时降级返回 nil' do
        allow(Scinote::AiEln::Formulation).to receive(:create!).and_raise('db down')
        expect(writer.write(record, team: team, created_by: user)).to be_nil
      end
    end
  end
end
