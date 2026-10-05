# frozen_string_literal: true

module Scinote
  module AiEln
    # SciNote 实验助手 Agent（ActiveAgent 实现 ai_eln 能力）
    #
    # 每个 action = 一个可被 Agent 调用的能力单元，复用 SciNote 现有读取 + Canaid 权限。
    # 上下文由控制器经 .with(...) 注入（映射为实例变量 @experiment / @protocol / @asset / @query）；
    # 权限已由控制器 before_action 守卫。
    class SciNoteAssistantAgent < ApplicationAgent
      # 实验摘要（PoC，对应 experiments/:experiment_id/summarize）
      def summarize_experiment
        raise "无法访问该实验或实验不存在。" unless @experiment

        text = experiment_brief(@experiment)
        prompt(message: <<~PROMPT)
          你是一名材料科学实验助手。请阅读以下实验的结构化信息，用中文给出简洁摘要，
          涵盖：实验目的、关键组分/配方、主要结果与结论、潜在风险或待办。
          保持客观，不要编造未提供的信息。

          #{text}
        PROMPT
      end

      # 协议 → 结构化配方（对应 protocols/:protocol_id/parse_recipe）
      def parse_recipe
        raise "无法访问该协议或协议不存在。" unless @protocol

        text = protocol_brief(@protocol)
        prompt(message: <<~PROMPT)
          你是一名配方科学家助手。请将以下实验协议文本解析为结构化配方（FORMULATION），
          用中文输出：组分列表（名称、角色如基料/增韧剂/填料/相容剂）、质量份或配比、
          关键工艺步骤、以及任何不确定项。不要编造协议中不存在的组分。

          #{text}
        PROMPT
      end

      # 附件解析（对应 attachments/:asset_id/parse）
      def parse_attachment
        raise "无法访问该附件或附件不存在。" unless @asset

        text = asset_brief(@asset)
        prompt(message: <<~PROMPT)
          你是一名科研文档助手。请阅读以下附件的元信息/文本内容，提取关键结构化信息
          （标题、关键参数、材料与配比、结论或待办），用中文输出。若仅能提供元信息，
          请注明"正文解析需 OCR/文本抽取管线（AI-102）"。

          #{text}
        PROMPT
      end

      # 全站语义检索（pgvector + neighbor 最近邻，对应 semantic_search）
      def semantic_search
        raise "未提供检索词。" if @query.to_s.strip.empty?

        begin
          query_embedding = embed(@query)
          hits = Scinote::AiEln::AiEmbedding
                   .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
                   .limit(5)
                   .to_a
          raise "语义索引为空，请先 populate ai_eln_ai_embeddings（pgvector + neighbor）。" if hits.empty?
        rescue StandardError => e
          raise "语义检索暂不可用（需 pgvector + neighbor + 已索引的 ai_eln_ai_embeddings）：#{e.message}"
        end

        lines = hits.map.with_index do |h, i|
          "#{i + 1}. [#{h.ai_embeddable_type}##{h.ai_embeddable_id}] 距离 #{(h.distance || 0).round(3)}\n" \
            "#{truncate(h.respond_to?(:content) ? h.content : '', 200)}"
        end
        prompt(message: <<~PROMPT)
          以下是与检索词"#{@query}"语义最相关的 SciNote 内容片段，请据此用中文总结
          最相关的发现，并列出对应来源（类型#ID）以便用户跳转。

          #{lines.join("\n\n")}
        PROMPT
      end

      private

      # 从实验模型抽取字段拼成给 LLM 的简介。
      def experiment_brief(experiment)
        [
          "名称: #{experiment.name}",
          "描述: #{experiment.description}",
          "状态: #{experiment.status}",
          "创建者: #{experiment.created_by&.full_name}",
          "开始日期: #{experiment.start_date}",
          "截止日期: #{experiment.due_date}"
        ].compact.join("\n")
      end

      # 协议简介：优先取步骤名，缺失时退回名称（VERIFY 各 SciNote Protocol 关联）
      def protocol_brief(protocol)
        parts = ["名称: #{protocol.name}", "描述: #{protocol.description}"]
        if protocol.respond_to?(:steps)
          protocol.steps.each.with_index do |step, i|
            parts << "步骤#{i + 1}: #{step.respond_to?(:name) ? step.name : step.to_s}"
          end
        end
        parts.compact.join("\n")
      rescue StandardError
        "名称: #{protocol.name}"
      end

      # 附件简介：元信息为主，正文抽取由 AI-102 OCR 管线负责（VERIFY Asset 字段名）
      def asset_brief(asset)
        [
          "文件名: #{asset.respond_to?(:file_name) ? asset.file_name : asset.name}",
          "描述: #{asset.respond_to?(:description) ? asset.description : ''}"
        ].compact.join("\n")
      end

      # VERIFY: RubyLLM embeddings API 形态（.embed 返回向量数组）
      def embed(text)
        RubyLLM.embed(text: text).vectors
      rescue StandardError => e
        raise "生成嵌入向量失败：#{e.message}"
      end

      def truncate(str, len)
        s = str.to_s
        s.length > len ? "#{s[0...len]}…" : s
      end
    end
  end
end
