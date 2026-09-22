# frozen_string_literal: true

module Scinote
  module AiEln
    # 语义检索向量表（ADR-0003，pgvector `vector` 类型）
    # 指向被索引实体的多态关联（StepText / ResultText / 附件文本）
    # 规格 §2.4 AI-301 混合检索
    class AiEmbedding < ActiveRecord::Base
      self.table_name = "ai_eln_ai_embeddings"

      belongs_to :ai_embeddable, polymorphic: true, optional: false
    end
  end
end
