# frozen_string_literal: true

# AI 协议解析作业台账（ai_parse_jobs）
#
# 存在理由：官方「Import with AI」对**每用户每天限 5 个作业**（知识库
# knowledgebase.scinote.net/en/knowledge/ai-protocol-parser）。为在本地复刻同一语义，
# 需要一张可计数的表：一次成功的 parse 调用落一行，配额判定 = 当日行数 < 5。
#
# ⚠ 与 addon 门控的分工：
#   · 门控（能不能用）  = Protocol.ai_parser_enabled?（ENV + ApplicationSettings + AddonSetting）
#   · 配额（今天还剩几次）= 本表按 (user_id, created_at) 的当日计数
#   两者独立：门控关了直接 403；门控开了但配额用尽 → 429。
#
# ⚠ 会话口径：按 UTC 日切分，与官方「每天」语义对齐（不引团队时区，避免跨日争议）。
#
# ⚠ 表名显式 self.table_name；类体裹 module Scinote::AiProtocols（与 eln_ui/access_control 同源铁律）。
class CreateAIParseJobs < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_parse_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :team, null: true, foreign_key: true
      t.string :mode, null: false, default: 'file_upload' # prompt_only / file_upload
      t.integer :steps_count, null: false, default: 0      # 供审计/用量分析
      t.timestamps
    end

    # 配额查询主路径：where(user_id:).where(created_at: today).count
    add_index :ai_parse_jobs, %i[user_id created_at]
  end
end
