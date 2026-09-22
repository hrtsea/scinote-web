# frozen_string_literal: true

class CreateAiElnTables < ActiveRecord::Migration[7.2]
  def change
    # 会话主表（规格 §4 ai_sessions）
    create_table :ai_eln_ai_sessions do |t|
      t.references :ai_sessionable, polymorphic: true, null: false
      t.references :user, null: false
      t.string :title
      t.timestamps
    end

    # 交互表 + 状态机（ADR-0004）
    create_table :ai_eln_ai_interactions do |t|
      t.references :ai_session, null: false, foreign_key: { to_table: :ai_eln_ai_sessions }
      t.integer :status, default: 0, null: false
      t.string :prompt_type
      t.text :prompt
      t.text :response
      t.string :model_name
      t.integer :token_usage
      t.timestamps
    end

    # 独立审计日志（ADR-0002，不写原生 Activity）
    create_table :ai_eln_ai_audit_logs do |t|
      t.references :ai_audit_loggable, polymorphic: true, null: true
      t.references :user, null: true
      t.string :model_name
      t.integer :token_usage
      t.integer :status
      t.timestamps
    end

    # 语义向量（ADR-0003，pgvector）
    create_table :ai_eln_ai_embeddings do |t|
      t.references :ai_embeddable, polymorphic: true, null: false
      t.text :chunk_text
      t.string :embedding_model
      t.timestamps
    end
  end
end
