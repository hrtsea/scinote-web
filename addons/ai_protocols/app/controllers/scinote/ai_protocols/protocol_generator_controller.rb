# frozen_string_literal: true

module Scinote
  module AiProtocols
    # Create-with-AI flow for protocol templates.
    #
    # Two surfaces:
    #   * Legacy server-rendered 3-step flow (/ai_protocols/*) — kept for no-JS fallback.
    #   * Official modal flow — fully async, JSON:API shaped, resource `parsed_protocols`:
    #       POST   /parsed_protocols            -> #create   (returns { data: { id } })
    #       GET    /parsed_protocols/:id        -> #show     (poll: status / valid / parsed_data / last_error)
    #       POST   /parsed_protocols/:id/import -> #import   (persists via ImportProtocolService)
    #       GET    /parsed_protocols/remaining_count -> { data: { daily_limit, remaining_count } }
    #
    # The controller only reuses host services (ProtocolImporters::ImportProtocolService,
    # ProtocolGenerator) and never touches core app/ code.
    class ProtocolGeneratorController < ::ApplicationController
      before_action :check_ai_parser_enabled

      # GET /parsed_protocols/remaining_count
      def remaining_count
        render json: {
          data: {
            daily_limit: Scinote::AiProtocols::ParseJob::DAILY_LIMIT,
            remaining_count: Scinote::AiProtocols::ParseJob.remaining_for(current_user)
          }
        }
      end

      # POST /parsed_protocols
      #   params: parsed_protocol[mode] (prompt_only|file_upload),
      #           parsed_protocol[prompt], parsed_protocol[file] (uploaded file)
      #   成功 -> { data: { id } }
      #   配额用尽 -> 429 { data: { error } }
      def create
        if Scinote::AiProtocols::ParseJob.remaining_for(current_user) <= 0
          return render json: {
            data: { error: t('ai_parser.modal.limit_reached', daily_limit: Scinote::AiProtocols::ParseJob::DAILY_LIMIT) }
          }, status: :too_many_requests
        end

        mode = params.dig(:parsed_protocol, :mode).presence || 'prompt_only'
        prompt = params.dig(:parsed_protocol, :prompt).to_s
        file = params.dig(:parsed_protocol, :file)

        source_text = if file.present?
                        Scinote::AiProtocols::TextExtractor.new.extract(file)
                      else
                        ''
                      end
        source_text = "#{t('scinote_ai_protocols.parse_instruction')}\n#{prompt}\n\n---\n#{source_text}" if prompt.present?

        job = Scinote::AiProtocols::ParseJob.create_processing!(
          user: current_user,
          team: current_team,
          mode: mode,
          prompt: prompt,
          source_text: source_text
        )
        render json: { data: { id: job.id } }
      rescue StandardError => e
        Rails.logger.error("AI parse create failed: #{e.message}")
        render json: { data: { error: t('ai_parser.modal.document_error') } }, status: :unprocessable_entity
      end

      # GET /parsed_protocols/:id
      # 轮询端点：首轮若仍 processing，则现场跑生成器并落库（异步状态机在首查时收敛）。
      def show
        job = Scinote::AiProtocols::ParseJob.where(user_id: current_user.id).find(params[:id])
        if job.processing?
          begin
            generated = generator.generate(job.source_text.presence || job.prompt.presence || '')
            job.complete!(generated)
          rescue StandardError => e
            job.fail!(e.message)
          end
        end

        render json: {
          data: {
            id: job.id,
            attributes: {
              status: job.status,
              valid: job.read_attribute(:parsed_valid),
              parsed_data: job.parsed_data_hash,
              last_error: job.last_error
            }
          }
        }
      end

      # POST /parsed_protocols/:id/import  (params: my_module_id, load_mode)
      def import
        job = Scinote::AiProtocols::ParseJob.where(user_id: current_user.id).find(params[:id])
        parsed = job.parsed_data_hash || {}
        load_mode = params[:load_mode].presence || 'replace'

        steps = Array(parsed['steps']).map.with_index do |step, index|
          h = { name: step['name'].to_s, position: index + 1, description: step['description'].to_s }
          tables = Array(step['tables']).map do |tbl|
            { name: tbl['name'].to_s, contents: Array(tbl['data']).to_json, metadata: '{}' }
          end
          h[:tables_attributes] = tables if tables.any?
          h
        end

        service = ProtocolImporters::ImportProtocolService.call(
          protocol_params: {
            name: parsed['name'].to_s,
            description: parsed['description'].to_s,
            protocol_type: :in_repository_draft
          },
          steps_params_json: steps.to_json,
          user: current_user,
          team: current_team
        )

        if service.succeed?
          render json: { data: { success: true, protocol_id: service.protocol.id } }
        else
          render json: { data: { error: t('ai_parser.modal.document_error') } }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("AI parse import failed: #{e.message}")
        render json: { data: { error: e.message } }, status: :unprocessable_entity
      end

      # --- 旧：服务端三步页（无 JS 降级路径，保留不动）---

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

      def legacy_create
        import_params = build_import_params
        service = ProtocolImporters::ImportProtocolService.call(
          protocol_params: import_params[:protocol_params].merge(protocol_type: :in_repository_draft),
          steps_params_json: import_params[:steps_params_json],
          user: current_user,
          team: current_team
        )

        if service.succeed?
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

      def extract_source_text
        protocol = params.require(:protocol).permit(:source_text, :source_file)
        uploaded = protocol[:source_file]
        return Scinote::AiProtocols::TextExtractor.new.extract(uploaded) if uploaded.present?

        protocol[:source_text].to_s
      end

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

      def check_ai_parser_enabled
        render_403 unless Protocol.ai_parser_enabled?
      end
    end
  end
end
