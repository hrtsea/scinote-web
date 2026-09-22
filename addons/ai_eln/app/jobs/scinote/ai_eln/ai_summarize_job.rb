# frozen_string_literal: true

module Scinote
  module AiEln
    # 后台任务：继承宿主 ActiveJob（adapter = delayed_job，规格写 Sidekiq 不实）
    # 大文件异步避免页面超时（规格 §3.1 性能）
    class AiSummarizeJob < ApplicationJob
      queue_as :default

      def perform(interaction_id)
        interaction = AiInteraction.find_by(id: interaction_id)
        return unless interaction

        prompt = interaction.prompt
        result = LlmAdapter.complete(prompt: prompt)

        interaction.update!(response: result, status: :success)
      rescue StandardError => e
        interaction&.update!(status: :failed, response: e.message)
        raise
      end
    end
  end
end
