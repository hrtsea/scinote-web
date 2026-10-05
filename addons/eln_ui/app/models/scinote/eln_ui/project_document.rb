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
      scope :required, -> { where(category: 'required').ordered }
      scope :other,    -> { where(category: 'other').ordered }

      def self.ordered
        order(:position, :id)
      end
    end
  end
end
