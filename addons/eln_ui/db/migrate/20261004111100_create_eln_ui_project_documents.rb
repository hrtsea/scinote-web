# frozen_string_literal: true

# 项目文档台账（挂在 Project 上）。存在理由：原生 SciNote 的附件走资产库
# （Asset/ActiveStorage，挂在 experiment/module 上），**没有项目级文档台账**——
# 「必传 5 类 / 版本 / 上传时间 / 是否已传」这种归档语义原生不存在。
#
# v1 是**登记台账**（metadata-only）：只登记名称/版本/时间/登记人，
# 不存文件本体；要挂文件本体时未来加 attachment（ActiveStorage）或 url 列。
class CreateElnUiProjectDocuments < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_project_documents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      # 'required'（必传：立项材料/任务书/年度计划/年度报告/结题报告这类）
      # 'other'   （其他：过程记录/参考资料）
      t.string :category, null: false, default: 'other'
      t.string :doc_type                     # 其他文档的类型（执行/评审/…），必传文档可空
      t.string :version                      # 'v2' / '—'
      t.boolean :uploaded, null: false, default: false
      t.date :uploaded_on
      t.references :uploader, foreign_key: { to_table: :users } # 登记人
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :eln_ui_project_documents, %i[project_id category position]
  end
end
