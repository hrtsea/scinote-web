# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    RSpec.describe ProtocolGenerator do
      # Intercept devise confirmable mail on create(:user) — no sender in test env.
      before do
        allow_any_instance_of(User).to receive(:send_confirmation_instructions)
        allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
      end

      let(:fake_client) do
        Class.new do
          def chat_with_schema(**_kwargs)
            {
              'name' => 'DNA Extraction',
              'description' => 'Extract genomic DNA from bacterial samples.',
              'steps' => [
                {
                  'name' => 'Lyse cells',
                  'description' => 'Add 100 µL lysis buffer and incubate at 37°C.',
                  'tables' => [
                    { 'name' => 'Reagents', 'data' => [['Reagent', 'Volume'], ['Lysis buffer', '100 µL']] }
                  ]
                },
                {
                  'name' => 'Purify',
                  'description' => 'Bind to column and wash.'
                }
              ]
            }
          end
        end.new
      end

      let(:generator) { described_class.new(llm_client: fake_client) }
      let(:source_text) { 'SOP: Lyse cells with buffer, then purify on a column.' }

      describe '#generate' do
        it 'returns protocol_params and a steps_params_json string' do
          result = generator.generate(source_text)

          expect(result[:protocol_params][:name]).to eq('DNA Extraction')
          expect(result[:protocol_params][:description]).to eq('Extract genomic DNA from bacterial samples.')

          steps = JSON.parse(result[:steps_params_json])
          expect(steps).to be_an(Array)
          expect(steps.size).to eq(2)
        end

        it 'assigns sequential positions and normalizes tables into tables_attributes' do
          steps = JSON.parse(generator.generate(source_text)[:steps_params_json])

          expect(steps[0]['position']).to eq(1)
          expect(steps[1]['position']).to eq(2)

          tables = steps[0]['tables_attributes']
          expect(tables.size).to eq(1)
          expect(tables[0]['name']).to eq('Reagents')
          expect(JSON.parse(tables[0]['contents'])).to eq([['Reagent', 'Volume'], ['Lysis buffer', '100 µL']])
          expect(tables[0]['metadata']).to eq('{}')
        end

        it 'omits tables_attributes when a step has no tables' do
          steps = JSON.parse(generator.generate(source_text)[:steps_params_json])
          expect(steps[1]).not_to have_key('tables_attributes')
        end

        it 'invokes the LLM client once' do
          expect(fake_client).to receive(:chat_with_schema).once.and_call_original
          generator.generate(source_text)
        end
      end

      describe 'contract with ImportProtocolService' do
        let(:user) { create(:user, confirmed_at: Time.current) }
        let(:team) { create(:team, created_by: user) }

        it 'produces a protocol that ImportProtocolService can persist' do
          generated = generator.generate(source_text)
          # The caller (Create-with-AI UI) supplies the repository protocol_type;
          # here we mirror that by merging a valid type before persisting.
          service = ProtocolImporters::ImportProtocolService.call(
            protocol_params: generated[:protocol_params].merge(protocol_type: :in_repository_draft),
            steps_params_json: generated[:steps_params_json],
            user:,
            team:
          )

          expect(service.succeed?).to be(true), "ImportProtocolService errors: #{service.errors.inspect}"
          expect(service.protocol).to be_persisted
          expect(service.protocol.steps.count).to eq(2)
          expect(service.protocol.steps.first.tables.count).to eq(1)
        end
      end
    end
  end
end
