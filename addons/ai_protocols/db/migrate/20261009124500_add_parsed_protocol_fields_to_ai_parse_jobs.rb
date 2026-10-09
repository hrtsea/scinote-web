# frozen_string_literal: true

# 为 ai_parse_jobs 增加异步解析任务状态机所需的字段。
# 见 app/models/scinote/ai_protocols/parse_job.rb 的状态机说明。
class AddParsedProtocolFieldsToAIParseJobs < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_parse_jobs, :status, :string, null: false, default: 'processing'
    add_column :ai_parse_jobs, :parsed_valid, :boolean, null: false, default: false
    add_column :ai_parse_jobs, :parsed_data, :text
    add_column :ai_parse_jobs, :last_error, :text
    add_column :ai_parse_jobs, :prompt, :text
    add_column :ai_parse_jobs, :source_text, :text
  end
end
