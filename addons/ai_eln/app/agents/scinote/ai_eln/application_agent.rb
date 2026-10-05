# frozen_string_literal: true

module Scinote
  module AiEln
    # ActiveAgent 应用级基类（"Agents are Controllers"）
    # 所有 ai_eln 能力 Agent 继承此类。
    #
    # 推理后端：RubyLLM -> DeepSeek（见宿主 config/active_agent.yml）。
    # generate_with 可在此统一指定；各 Agent 也可覆盖。
    #
    # 注：文件位于 app/agents/scinote/ai_eln/ 子目录 —— Zeitwerk 按目录结构
    # 推断常量命名空间（与 app/models/scinote/ai_eln/ 惯例一致），
    # isolate_namespace 不改变这一点。参考：https://docs.activeagents.ai
    class ApplicationAgent < ActiveAgent::Base
      generate_with :ruby_llm, model: "deepseek-chat"
    end
  end
end
