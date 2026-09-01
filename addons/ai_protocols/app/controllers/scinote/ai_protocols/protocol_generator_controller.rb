# frozen_string_literal: true

module Scinote
  module AiProtocols
    # Create-with-AI flow for protocol templates.
    #
    # The flow is fully self-contained inside the addon:
    #   GET  /ai_protocols/new     -> text input
    #   POST /ai_protocols/preview -> calls ProtocolGenerator, renders an editable form
    #   POST /ai_protocols         -> persists an in_repository_draft Protocol
    #
    # It never touches core app/ code; it only reuses the host's
    # ProtocolImporters::ImportProtocolService to persist the result.
    class ProtocolGeneratorController < ::ApplicationController
      before_action :check_ai_parser_enabled
      before_action :check_generate_permission

      def new; end

      def preview
        @source_text = extract_source_text
        generated = generator.generate(@source_text)
        @protocol_params = generated[:protocol_params]
        @steps = JSON.parse(generated[:steps_params_json])
      rescue StandardError => e
        flash.now[:alert] = t('scinote_ai_protocols.generate_error', message: e.message)
        @protocol_params = { name: '', description: '' }
        @steps = []
        render :new
      end

      def create
        import_params = build_import_params
        service = ProtocolImporters::ImportProtocolService.call(
          protocol_params: import_params[:protocol_params].merge(protocol_type: :in_repository_draft),
          steps_params_json: import_params[:steps_params_json],
          user: current_user,
          team: current_team
        )

        if service.succeed?
          # The engine isolates its namespace and is mounted at '/', so the bare
          # `protocol_path` helper would resolve against the engine's routes
          # (which have no `protocols` resource). Reference the host application
          # explicitly via `main_app.`.
          redirect_to main_app.protocol_path(service.protocol.id),
                      notice: t('scinote_ai_protocols.created')
        else
          @protocol_params = import_params[:protocol_params]
          @steps = JSON.parse(import_params[:steps_params_json])
          @source_text = params.dig(:protocol, :source_text).to_s
          flash.now[:alert] = t('scinote_ai_protocols.create_error', message: service.errors.inspect)
          render :preview
        end
      end

      private

      def generator
        @generator ||= Scinote::AiProtocols::ProtocolGenerator.new
      end

      # Source text comes from either the editable textarea or an uploaded file.
      # An uploaded file is run through TextExtractor (plain text read directly,
      # PDF via pdftotext) before being handed to the generator.
      def extract_source_text
        protocol = params.require(:protocol).permit(:source_text, :source_file)
        uploaded = protocol[:source_file]
        return Scinote::AiProtocols::TextExtractor.new.extract(uploaded) if uploaded.present?

        protocol[:source_text].to_s
      end

      def check_ai_parser_enabled
        render_403 unless Protocol.ai_parser_enabled?
      end

      def check_generate_permission
        render_403 unless can_generate_protocol_with_ai?(current_user, current_team)
      end

      # Convert the editable form submission back into the shape that
      # ImportProtocolService expects.
      def build_import_params
        protocol = params.require(:protocol).permit(
          :name, :description,
          steps: [:name, :description, { tables: %i[name data] }]
        )
        steps = Array(protocol[:steps]&.values).map.with_index do |step, index|
          step_hash = {
            name: step[:name].to_s,
            position: index + 1,
            description: step[:description].to_s
          }
          tables = normalize_tables_from_params(step[:tables])
          step_hash[:tables_attributes] = tables if tables.any?
          step_hash
        end

        {
          protocol_params: {
            name: protocol[:name].to_s,
            description: protocol[:description].to_s
          },
          steps_params_json: steps.to_json
        }
      end

      def normalize_tables_from_params(tables)
        Array(tables&.values).map do |table|
          {
            name: table[:name].to_s,
            contents: Array(JSON.parse(table[:data].presence || '[]')).to_json,
            metadata: '{}'
          }
        end
      end
    end
  end
end
