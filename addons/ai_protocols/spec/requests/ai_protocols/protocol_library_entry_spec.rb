# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    RSpec.describe 'AI Protocol library entry button', type: :request do
      include Devise::Test::IntegrationHelpers
      let(:user) { create(:user, confirmed_at: Time.current) }

      before do
        allow_any_instance_of(User).to receive(:send_confirmation_instructions)
        allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
        create(:team, :change_user_team, created_by: user)
        sign_in user
        allow(Protocol).to receive(:ai_parser_enabled?).and_return(true)
        # The injected button reuses the generate permission; authorise through
        # the underlying grant (canaid registers per request in the test env).
        allow_any_instance_of(Team).to receive(:permission_granted?).and_return(true)
      end

      it 'shows the Create with AI button on the protocol library page' do
        get protocols_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Create with AI')
        expect(response.body).to include('id="createProtocolWithAi"')
        expect(response.body).to include('/ai_protocols/new')
      end

      it 'hides the button when the user lacks the generate permission' do
        allow_any_instance_of(Team).to receive(:permission_granted?).and_return(false)
        get protocols_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('id="createProtocolWithAi"')
      end

      it 'hides the button when the AI parser is disabled' do
        allow(Protocol).to receive(:ai_parser_enabled?).and_return(false)
        get protocols_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('id="createProtocolWithAi"')
      end
    end
  end
end
