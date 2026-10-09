# frozen_string_literal: true

module Scinote
  module AiProtocols
    # Turns free text / extracted PDF text into a structured protocol that is
    # directly consumable by the host's ProtocolImporters::ImportProtocolService.
    #
    # The LLM is constrained via an OpenAI-compatible JSON schema so its output
    # already matches the shape we normalize into:
    #   { protocol_params: { name:, description: },
    #     steps_params_json: "<json array of step objects>" }
    # where each step has name / position / description / tables_attributes
    # (name, contents as a JSON-encoded 2D array, metadata as a JSON-encoded hash).
    class ProtocolGenerator
      SYSTEM_PROMPT = <<~PROMPT
        You are a laboratory protocol structuring assistant for SciNote, an Electronic Lab Notebook.
        Convert the user's free-text procedure, SOP, or extracted PDF text into a structured, reusable protocol.

        Rules:
        - Provide a concise protocol "name" and an overall "description".
        - Split the procedure into ordered "steps". Each step has a short "name" and a detailed "description" written in Markdown.
        - For any tabular data inside a step, include "tables": each with a "name" and "data" as a 2D array of strings (the first row is the header row).
        - Never invent results, measurements, or values that are not present in the source. If absent, leave them out.
        - Respond ONLY with the structured object defined by the provided JSON schema.
      PROMPT

      # 🔴 llm_client 的解析必须**延迟到 generate 内**：Scinote::AiProtocols.llm_client
      #   在未配置 base_url 时会直接 raise（LlmClient#validate!）。若把它放进默认参数，
      #   构造 ProtocolGenerator.new 就炸，controller 的 rescue 只能落 fail!（实测：
      #   /parsed_protocols/:id 首查即 error）。延迟到方法体，才能被下面 rescue 捕获 → 走 heuristic。
      def initialize(llm_client: nil)
        @llm_client = llm_client
      end

      # source_text: raw procedure text (from user input or extracted PDF).
      # Returns a hash ready to be passed to ProtocolImporters::ImportProtocolService.call:
      #   { protocol_params: { name:, description: },
      #     steps_params_json: "<json string of step objects>" }
      def generate(source_text, name: nil)
        client = @llm_client || Scinote::AiProtocols.llm_client
        raw = client.chat_with_schema(
          system_prompt: SYSTEM_PROMPT,
          user_prompt: source_text,
          schema:,
          schema_name: 'protocol'
        )
        normalize(raw, name:)
      rescue StandardError => e
        # 本地复刻兜底：未配置 LLM（OpenAI 兼容服务）时，用启发式规则把源文本
        # 结构化为协议，保证 Import with AI 流程在离线环境也可端到端点通。
        # 🔴 heuristic 产出的是「LLM 原始形状」（name/description/steps），必须再过
        #   normalize 转成调用方（ParseJob#complete!）期望的 { protocol_params:, steps_params_json: }，
        #   否则 complete! 里 generated[:protocol_params] 为 nil → nil[:name] 炸。
        Rails.logger.warn("AI parser LLM unavailable (#{e.message}); using heuristic fallback")
        normalize(heuristic(source_text, name: name), name: name)
      end

      # 启发式回退：把自由文本按行拆成步骤；首行（较短）作为协议名。
      # 产物形状与 LLM 输出一致，便于上层直接消费。
      def heuristic(source_text, name:)
        lines = source_text.to_s.lines.map(&:strip).reject(&:empty?)
        # 提示词模式下 source_text 以「指令前缀」开头（parse_instruction，形如
        # "Follow this instruction…:"），它不该被当成协议名 —— 先剔除这类标签行。
        if lines.first && (lines.first.end_with?(':') || lines.first.match?(/instruction/i))
          lines.shift
        end
        title = if name.present?
                  name
                elsif lines.first && lines.first.length < 80
                  lines.first
                else
                  'Generated protocol'
                end
        body = lines.drop(title == lines.first ? 1 : 0)
        body = ['Describe the procedure in a few steps.'] if body.empty?
        {
          'name' => title.to_s,
          'description' => 'Protocol generated from the provided input (heuristic fallback — no LLM configured).',
          'steps' => body.each_with_index.map do |line, index|
            { 'name' => "Step #{index + 1}", 'description' => line }
          end
        }
      end

      private

      attr_reader :llm_client

      # OpenAI-compatible strict JSON schema. `strict: true` requires every object
      # to set additionalProperties: false and list all properties in `required`,
      # which is why optional fields (authors, protocol_type) are intentionally omitted.
      def schema
        {
          type: 'object',
          additionalProperties: false,
          properties: {
            name: { type: 'string' },
            description: { type: 'string' },
            steps: {
              type: 'array',
              items: {
                type: 'object',
                additionalProperties: false,
                properties: {
                  name: { type: 'string' },
                  description: { type: 'string' },
                  tables: {
                    type: 'array',
                    items: {
                      type: 'object',
                      additionalProperties: false,
                      properties: {
                        name: { type: 'string' },
                        data: { type: 'array', items: { type: 'array', items: { type: 'string' } } }
                      },
                      required: %w[name data]
                    }
                  }
                },
                required: %w[name description]
              }
            }
          },
          required: %w[name description steps]
        }
      end

      def normalize(raw, name:)
        steps = Array(raw['steps']).each_with_index.map do |step, index|
          step_hash = {
            name: step['name'].to_s,
            position: index + 1,
            description: step['description'].to_s
          }
          tables = normalize_tables(step['tables'])
          step_hash[:tables_attributes] = tables if tables.any?
          step_hash
        end

        protocol_params = { name: (name || raw['name']).to_s, description: raw['description'].to_s }

        {
          protocol_params:,
          steps_params_json: steps.to_json
        }
      end

      def normalize_tables(tables)
        Array(tables).map do |table|
          {
            name: table['name'].to_s,
            contents: Array(table['data']).to_json,
            metadata: '{}'
          }
        end
      end
    end
  end
end
