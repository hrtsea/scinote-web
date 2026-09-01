# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    RSpec.describe 'Import with AI (file upload)', type: :request do
      include Devise::Test::IntegrationHelpers
      let(:user) { create(:user, confirmed_at: Time.current) }

      let(:fake_client) do
        Class.new do
          def chat_with_schema(**_kwargs)
            {
              'name' => 'DNA Extraction',
              'description' => 'Extract genomic DNA from bacterial samples.',
              'steps' => [
                {
                  'name' => 'Lyse cells',
                  'description' => 'Add 100 µL lysis buffer and incubate at 37°C.'
                }
              ]
            }
          end
        end.new
      end

      before do
        allow_any_instance_of(User).to receive(:send_confirmation_instructions)
        allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
        create(:team, :change_user_team, created_by: user)
        sign_in user
        allow(Protocol).to receive(:ai_parser_enabled?).and_return(true)
        allow(Scinote::AiProtocols::LlmClient).to receive(:for).and_return(fake_client)
        allow_any_instance_of(Team).to receive(:permission_granted?).and_return(true)
      end

      it 'extracts and previews an uploaded .txt file' do
        temp = Tempfile.new(['sop', '.txt'])
        temp.write('Lyse cells with 100 uL lysis buffer.')
        temp.rewind
        upload = Rack::Test::UploadedFile.new(temp.path, 'text/plain', original_filename: 'sop.txt')
        post '/ai_protocols/preview', params: { protocol: { source_file: upload } }
        temp.close!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('DNA Extraction')
      end

      it 'previews an uploaded PDF by delegating extraction to TextExtractor' do
        allow_any_instance_of(Scinote::AiProtocols::TextExtractor).to receive(:extract).and_return('PDF extracted text')
        temp = Tempfile.new(['doc', '.pdf'])
        temp.write('%PDF-1.4')
        temp.rewind
        upload = Rack::Test::UploadedFile.new(temp.path, 'application/pdf', original_filename: 'doc.pdf')
        post '/ai_protocols/preview', params: { protocol: { source_file: upload } }
        temp.close!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('DNA Extraction')
      end

      it 'returns to the form with an alert on unsupported file types' do
        temp = Tempfile.new(['sheet', '.xlsx'])
        temp.write('sheet')
        temp.rewind
        upload = Rack::Test::UploadedFile.new(temp.path, 'application/vnd.ms-excel', original_filename: 'sheet.xlsx')
        post '/ai_protocols/preview', params: { protocol: { source_file: upload } }
        temp.close!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Create Protocol with AI')
        expect(response.body).to include('Unsupported file type')
      end
    end
  end
end
