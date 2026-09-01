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

      def initialize(llm_client: LlmClient.for)
        @llm_client = llm_client
      end

      # source_text: raw procedure text (from user input or extracted PDF).
      # Returns a hash ready to be passed to ProtocolImporters::ImportProtocolService.call:
      #   { protocol_params: { name:, description: },
      #     steps_params_json: "<json string of step objects>" }
      def generate(source_text, name: nil)
        raw = @llm_client.chat_with_schema(
          system_prompt: SYSTEM_PROMPT,
          user_prompt: source_text,
          schema:,
          schema_name: 'protocol'
        )
        normalize(raw, name:)
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
