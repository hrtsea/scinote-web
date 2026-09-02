# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    RSpec.describe 'AI Protocol generation', type: :request do
      include Devise::Test::IntegrationHelpers
      let(:user) { create(:user, confirmed_at: Time.current) }
      # The team is created inside the `before` block (created_by: user) so the
      # Devise mailer stub is already active and the user's current_team is set.

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
                { 'name' => 'Purify', 'description' => 'Bind to column and wash.' }
              ]
            }
          end
        end.new
      end

      before do
        # Devise confirmable sends a mail on create(:user); the test mailer has no
        # sender configured in this environment, so intercept the calls.
        allow_any_instance_of(User).to receive(:send_confirmation_instructions)
        allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
        # Build the team (and make it current for the user) so the core
        # before_actions resolve a real current_team.
        create(:team, :change_user_team, created_by: user)
        sign_in user
        allow(Protocol).to receive(:ai_parser_enabled?).and_return(true)
        allow(Scinote::AiProtocols).to receive(:llm_client).and_return(fake_client)
        # In the test env canaid's to_prepare runs per request, so the
        # `can_generate_protocol_with_ai?` helper is not registered until the
        # request fires. We authorise through the underlying grant instead of
        # stubbing the not-yet-defined helper.
        allow_any_instance_of(Team).to receive(:permission_granted?).and_return(true)
      end

      it 'renders the input page' do
        get '/ai_protocols/new'
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Create Protocol with AI')
      end

      it 'generates a preview with editable fields' do
        post '/ai_protocols/preview', params: { protocol: { source_text: 'Lyse cells' } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('DNA Extraction')
        expect(response.body).to include('protocol[steps][0][name]')
        expect(response.body).to include('protocol[steps][0][tables][0][name]')
      end

      it 'persists an in_repository_draft protocol on create' do
        post '/ai_protocols', params: {
          protocol: {
            name: 'DNA Extraction',
            description: 'Extract genomic DNA.',
            steps: {
              '0' => {
                name: 'Lyse cells',
                description: 'Add 100 µL lysis buffer.',
                tables: { '0' => { name: 'Reagents', data: '[["Reagent","Volume"],["Lysis buffer","100 µL"]]' } }
              },
              '1' => { name: 'Purify', description: 'Bind to column and wash.' }
            }
          }
        }
        expect(response).to redirect_to(main_app.protocol_path(Protocol.last))
        expect(Protocol.last.protocol_type).to eq('in_repository_draft')
        expect(Protocol.last.steps.count).to eq(2)
        expect(Protocol.last.steps.first.tables.count).to eq(1)
      end

      it 'blocks generation without the generate permission' do
        allow_any_instance_of(Team).to receive(:permission_granted?).and_return(false)
        post '/ai_protocols/preview', params: { protocol: { source_text: 'x' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'blocks access when ai_parser is disabled' do
        allow(Protocol).to receive(:ai_parser_enabled?).and_return(false)
        get '/ai_protocols/new'
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
