# frozen_string_literal: true

# 项目文档台账（eln_ui_project_documents）—— 原生附件是资产不是归档台账。
# uploaded 驱动「归档完整性校验」：缺必传文档 → 归档导出不可用（前端 missingDocs）。
module Scinote
  module ElnUi
    class ProjectDocument < ActiveRecord::Base
      self.table_name = 'eln_ui_project_documents'

      belongs_to :project, class_name: '::Project', inverse_of: false
      belongs_to :uploader, class_name: '::User', optional: true

      # category 取值：'required'（必传）/ 'other'（其他）
      # ⚠ ordered 用 scope 而不是 `def self.ordered`：同目录的 ProjectCostItem /
      #   DesignVariable / ProjectMetric 三个 model 都是 `scope :ordered`，这里写成类方法
      #   后，scope 里 `where(...).ordered` 得靠 Relation 的方法委派才找工作，读起来很绕。
      scope :ordered, -> { order(:position, :id) }
      scope :required, -> { where(category: 'required').ordered }
      scope :other,    -> { where(category: 'other').ordered }

      # 文件本体（2026-10-11 上线，供页头「上传任务书」用）。
      # 走宿主 ActiveStorage，不自建文件表 —— 同 addon 的 ReceiptVerification#photos
      # 已经把这条路跑通了（其注释点明先例 form_repository_rows_field_value.rb:19）。
      # ⚠ 这里只声明：附件大小/类型/清理策略沿用宿主既有约定，不另立一套。
      has_one_attached :file
    end
  end
end
