# frozen_string_literal: true

# ELN UI —— 资源申请单详情页数据装配
#
# 数据源：eln_ui_resource_applications 单条 + 关联 project + requestor +
# group_reviewer + project_reviewer + items JSON 解析 + 审批时间线派生。
#
# 权限：申请单 → 所属项目 → readable_by_user(current_user)（同项目可看，
# 含其他成员的申请；不要求 requestor == current_user，符合原型「全员可见 + 提交人列」语义）。

module Scinote
  module ElnUi
    class ResApplyDetailPayload
      DATE_FMT = '%Y-%m-%d %H:%M'

      class << self
        def call(user:, team:, no:)
          new(user: user, team: team, no: no).call
        end
      end

      def initialize(user:, team:, no:)
        @user = user
        @team = team
        @no = no
      end

      def call
        app = Scinote::ElnUi::ResourceApplication.find_by(no: @no)
        return { notFound: true } if app.nil?

        unless readable_project?(app.project)
          return { forbidden: true }
        end

        {
          notFound: false,
          forbidden: false,
          application: application_block(app),
          items: items_block(app),
          timeline: timeline_block(app),
          approvals: approvals_block(app),
          meta: meta_block(app)
        }
      end

      private

      def readable_project?(project)
        return false if project.nil?
        return false unless project.team_id == @team.id

        ::Project.where(id: project.id).readable_by_user(@user).exists?
      end

      def application_block(app)
        {
          id: app.id,
          no: app.no,
          status: app.status,
          statusLabel: status_label(app.status),
          project: app.project ? project_block(app.project) : nil,
          requestor: user_block(app.requestor),
          groupReviewer: user_block(app.group_reviewer),
          projectReviewer: user_block(app.project_reviewer),
          note: app.note.to_s,
          createdAt: dt(app.created_at),
          submittedAt: dt(app.submitted_at),
          groupApprovedAt: dt(app.group_approved_at),
          projectApprovedAt: dt(app.project_approved_at),
          completedAt: dt(app.completed_at)
        }
      end

      def project_block(p)
        {
          id: p.id,
          name: p.name.to_s,
          code: "##{p.id}"
        }
      end

      def user_block(u)
        return nil if u.nil?

        { id: u.id, name: (u.full_name.presence || u.email).to_s }
      end

      def items_block(app)
        app.item_list.map do |it|
          kind = (it['kind'] || it[:kind] || 'material').to_s
          qty = (it['qty'] || it[:qty] || 0).to_d
          unit = (it['unit'] || it[:unit] || '').to_s
          unit_price = (it['unit_price'] || it[:unit_price] || 0).to_d
          {
            kind: kind,
            kindLabel: kind == 'service' ? '测试表征' : '材料',
            name: (it['name'] || it[:name]).to_s,
            qty: "#{qty} #{unit}".strip,
            qtyRaw: qty,
            unit: unit,
            unitPrice: format_money(unit_price),
            amount: format_money(qty * unit_price),
            repositoryRowId: it['repository_row_id'] || it[:repository_row_id]
          }
        end
      end

      def timeline_block(app)
        events = []
        events << { key: 'created',   at: dt(app.created_at),         label: '创建申请', by: user_block(app.requestor) } if app.created_at
        events << { key: 'submitted', at: dt(app.submitted_at),       label: '提交审批', by: user_block(app.requestor) } if app.submitted_at
        events << { key: 'group',     at: dt(app.group_approved_at),  label: '小组通过', by: user_block(app.group_reviewer) }  if app.group_approved_at
        events << { key: 'project',   at: dt(app.project_approved_at),label: '项目通过', by: user_block(app.project_reviewer) } if app.project_approved_at
        events << { key: 'completed', at: dt(app.completed_at),       label: '已出库',   by: nil } if app.completed_at
        events << { key: 'rejected',  at: nil, label: '已驳回', by: nil } if app.rejected?
        events
      end

      def approvals_block(app)
        {
          groupRequired:  !app.group_approved_at && app.submitted?,
          projectRequired: app.group_approved? && !app.project_approved_at,
          canApproveGroup:  can_approve?(app, :group),
          canApproveProject: can_approve?(app, :project)
        }
      end

      def can_approve?(app, level)
        return false if app.nil? || @user.nil?

        case level
        when :group
          app.submitted? && !app.group_approved? && same_team?(app) && !own_application?(app)
        when :project
          app.group_approved? && !app.project_approved? && same_team?(app) && !own_application?(app)
        else
          false
        end
      end

      def same_team?(app)
        app.project && app.project.team_id == @team.id
      end

      def own_application?(app)
        app.requestor_id == @user.id
      end

      def meta_block(app)
        {
          team: @team.name.to_s,
          canEdit: app.draft? && own_application?(app),
          canSubmit: app.draft? && own_application?(app),
          # 终审通过 → 出库确认人可标记完成（SCN-RES-APPROVE-3 的人工执行步；
          # 自动出库是下一阶段，见 ResourceApplicationWorkflow 头注释）
          canComplete: app.project_approved? && same_team?(app) && !own_application?(app),
          isRequestor: own_application?(app)
        }
      end

      STATUS_LABELS = {
        'draft'            => '草稿',
        'submitted'        => '待审批',
        'group_approved'   => '小组通过',
        'project_approved' => '已通过',
        'rejected'         => '驳回',
        'completed'        => '已完成'
      }.freeze

      def status_label(s)
        STATUS_LABELS[s] || s.to_s
      end

      def format_money(v)
        v = v.to_d
        int = v.round.to_i
        formatted = int == v ? int.to_s : format('%.2f', v)
        "¥ #{formatted.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end

      def dt(value)
        return nil if value.blank?

        value.respond_to?(:strftime) ? value.strftime(DATE_FMT) : value.to_s
      end
    end
  end
end
