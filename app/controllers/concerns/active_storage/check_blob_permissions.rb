# frozen_string_literal: true

module ActiveStorage
  module CheckBlobPermissions
    extend ActiveSupport::Concern

    included do
      before_action :check_read_permissions
    end

    private

    def check_read_permissions
      return render_404 if @blob.attachments.blank?

      render_403 unless @blob.attachments.any? { |attachment| check_attachment_read_permissions(attachment) }
    end

    def check_attachment_read_permissions(attachment)
      current_user.permission_team = attachment.record.team if attachment.record.respond_to?(:team)

      return false if attachment.record.blank?

      case attachment.record_type
      when 'Asset'
        check_asset_read_permissions(attachment.record)
      when 'TinyMceAsset'
        check_tinymce_asset_read_permissions(attachment.record)
      when 'Experiment'
        can_read_experiment?(attachment.record)
      when 'StorageLocation'
        can_read_storage_location?(attachment.record)
      when 'Report'
        can_read_project?(attachment.record.project)
      # ADR-0050 D2（eln_ui addon）：项目文档台账附件。与 Report 分支同构 ——
      #   record.project + session 的 permission_team（set_project 已把项目收口在
      #   current_team 内才可达，故 team 上下文天然一致）。
      #   必传/其他文档行的预览/下载端点（project_detail#preview_document /
      #   download_document）redirect 到 rails_blob_path，宿主的这一关是**第二道**：
      #   端点管「谁能发起」，这里管「URL 本身可验证」——signed_id 即使外溢也会被再查一次。
      when 'Scinote::ElnUi::ProjectDocument'
        can_read_project?(attachment.record.project)
      when 'ReportTemplate'
        protocol = attachment.record.subject
        can_read_protocol_in_module?(protocol) || can_read_protocol_in_repository?(protocol)
      when 'AnalyticalReport'
        case attachment.record.reference_type
        when 'MyModule'
          can_read_protocol_in_module?(attachment.record.reference.protocol)
        when 'Experiment'
          can_read_experiment?(attachment.record.reference)
        else
          false
        end
      when 'User'
        # No read restrictions for avatars
        true
      when 'ZipExport', 'TeamZipExport'
        attachment.record.user == current_user
      when 'TempFile'
        attachment.record.session_id == request.session_options[:id].to_s
      else
        false
      end
    end

    def check_asset_read_permissions(asset)
      if asset.step
        protocol = asset.step.protocol
        can_read_protocol_in_module?(protocol) || can_read_protocol_in_repository?(protocol)
      elsif asset.result
        result = asset.result
        can_read_result?(result)
      elsif asset.repository_cell
        repository = asset.repository_cell.repository_column.repository
        can_read_repository?(repository)
      else
        false
      end
    end

    def check_tinymce_asset_read_permissions(asset)
      return true if asset.object.nil? && can_read_team?(asset.team)

      case asset.object_type
      when 'MyModule'
        can_read_my_module?(asset.object)
      when 'Protocol'
        can_read_protocol_in_module?(asset.object) || can_read_protocol_in_repository?(asset.object)
      when 'ResultText'
        can_read_result?(asset.object.result)
      when 'StepText'
        can_read_protocol_in_module?(asset.object.step.protocol) ||
          can_read_protocol_in_repository?(asset.object.step.protocol)
      else
        false
      end
    end
  end
end
