# frozen_string_literal: true

# ELN UI —— 资源申请单写流程（OPEN-10 · REQ-RES-APPLY / REQ-RES-APPROVE）
#
# 状态机（SCN-RES-APPROVE-1~5，二段式审批）：
#   draft --submit--> submitted --approve_group--> group_approved
#         --approve_project--> project_approved --complete--> completed
#   submitted / group_approved --reject--> rejected
#
# 权限闸门口径（⚠ 与 ResApplyDetailPayload#can_approve? 完全同源）：
#   submit          → requestor 本人
#   approve_group   → 同队 + 非本人（初审）
#   approve_project → 同队 + 非本人（终审）
#   reject          → 同队 + 非本人（两阶段均可驳）
#   complete        → 同队 + 非本人（出库确认人语义）
#   ⚠ 「小组组长 / 项目负责人」的角色精判挂在 OPEN-1（Owner vs supervised_by+
#     project_head 职责边界）上 —— 未决前先用宽口径，OPEN-1 收敛后在这里
#     与 payload 两处一起收紧，不许一处宽一处窄。
#
# 驳回溯源（不加列、不动生产表）：复用现有 reviewer 字段记「谁驳的」，
#   submitted 阶段 → group_reviewer；group_approved 阶段 → project_reviewer；
#   驳回原因以「驳回原因：…」前缀追加进 note。
#
# ⚠ SCN-RES-APPROVE-3（材料类终审通过自动出库扣库存）**本轮不自动执行**：
#   需要 items 绑定 repository_row_id + 出库任务关联（申请单 items 目前
#   repositoryRowId 恒 null），是下一阶段。终审通过后停在 project_approved，
#   由人工在原生库存页出库，确认后点「标记完成」→ completed。
module Scinote
  module ElnUi
    class ResourceApplicationWorkflow
      # 对外可预期的业务错误（controller 转 422，不炸 500）
      class WorkflowError < StandardError; end

      ACTIONS = %w[submit approve_group approve_project reject complete].freeze

      class << self
        # user/team 由 controller 注入；no = 业务编号；type/reason 来自表单
        def call(user:, team:, no:, type:, reason: nil)
          raise WorkflowError, "未知操作: #{type}" unless ACTIONS.include?(type.to_s)

          app = Scinote::ElnUi::ResourceApplication.find_by(no: no.to_s)
          raise WorkflowError, '申请单不存在' if app.nil?
          # ⚠ 类方法上下文 —— same_team? 是实例私有方法，这里必须内联（本轮 6 errors 根因）
          unless app.project && app.project.team_id == team&.id
            raise WorkflowError, '申请单不属于当前团队'
          end

          new(app: app, user: user, team: team).run(type.to_s, reason.to_s.presence)
        end

        # ------------------------------------------------------------
        # 新建申请（SCN-RES-APPLY-1）：表单直建草稿
        #   · 编号自动生成 SQ-YYYY-NNNN（当年前缀下最大序号 + 1；
        #     seed 演示单 SQ-2026-7777 也计入 max，新单会排到 7778 —— 是特性不是 bug）
        #   · 权限：登录团队成员即可发起（审批闸门在实例侧另算）；
        #     项目必须属于当前 team（与 call 的团队口径一致）
        #   · 表单字段：project_id / kind / name / qty / unit / unit_price / purpose
        #     kind 白名单 material | service；qty 必须 > 0；name 必填；
        #     unit / unit_price / purpose 选填（unit_price 空 → 0，详情页显示 ¥0）
        # ------------------------------------------------------------
        # 表单字段逐个显式收进来（不再把 ActionController::Parameters 当参数往下传 ——
        # 服务层不该认识请求对象）；类型不硬转（controller 侧用 permit，见
        # res_apply_create_controller 的踩坑注），这里对 nil / 字符串一律业务判定。
        def create_draft(user:, team:, project_id:, kind:, name:, qty:, unit: nil, unit_price: nil, purpose: nil)
          raise WorkflowError, '请选择申请项目' if project_id.blank?

          project = ::Project.find_by(id: project_id)
          raise WorkflowError, '申请项目不存在' if project.nil?
          raise WorkflowError, '申请项目不属于当前团队' unless project.team_id == team&.id

          kind = kind.to_s
          raise WorkflowError, '资源类型必须为 material 或 service' unless %w[material service].include?(kind)

          name = name.to_s.strip
          raise WorkflowError, '请填写资源名称' if name.blank?

          qty = qty.to_d
          raise WorkflowError, '数量必须大于 0' unless qty.positive?

          begin
            app = Scinote::ElnUi::ResourceApplication.create!(
              no: next_no!,
              project: project,
              requestor: user,
              status: 'draft',
              note: purpose.to_s.strip.presence,
              item_list: [{
                'kind' => kind,
                'name' => name,
                'qty' => json_number(qty),
                'unit' => unit.to_s.strip,
                'unit_price' => json_number(unit_price.presence&.to_d || 0.to_d)
              }]
            )
          rescue ActiveRecord::RecordNotUnique
            # next_no!（读最大序号）与 create!（写编号）之间不是原子的，并发新建会撞成同一号。
            # 唯一索引就在这一行生效，重算一次序号即可；一直撞说明序号真用尽了。
            retry
          end

          { ok: true, no: app.no, id: app.id, status: app.status, statusLabel: '草稿' }
        rescue ActiveRecord::RecordInvalid => e
          raise WorkflowError, e.message
        end

        private

        # SQ-YYYY-NNNN：当年前缀下最大序号 + 1（LIKE 走 no 列，值由本类生成、格式受
        # model 校验约束，无注入面）。>9999 直接报错（model 格式校验只认 4 位序号）。
        # 只有 create_draft 会调它，不该出现在类公开面上。
        def next_no!
          prefix = "SQ-#{Date.current.year}-"
          max_seq = Scinote::ElnUi::ResourceApplication
                      .where('no LIKE ?', "#{prefix}%")
                      .pluck(:no)
                      .filter_map { |n| n.delete_prefix(prefix).to_i if n.start_with?(prefix) }
                      .max || 0
          raise WorkflowError, "当年申请编号已用尽（#{max_seq}）" if max_seq >= 9999

          format('%s%04d', prefix, max_seq + 1)
        end

        # BigDecimal 落 jsonb 会被序列化成字符串（"20.0"）—— 整数就存 Integer，
        # 小数存 Float，保持 items JSON 干净（详情页 .to_d 读回无差别）
        def json_number(value)
          value.frac.zero? ? value.to_i : value.to_f
        end
      end

      def initialize(app:, user:, team:)
        @app = app
        @user = user
        @team = team
      end

      # 五个动作显式分派。type 来自用户表单，不拿它当 send 的目标 —— 白名单在 .call，
      # 这里再落一遍 case：加动作时看这个方法就知道要改什么，不用追着白名单跑。
      def run(type, reason)
        case type
        when 'submit'          then submit(reason)
        when 'approve_group'   then approve_group(reason)
        when 'approve_project' then approve_project(reason)
        when 'reject'          then reject(reason)
        when 'complete'        then complete(reason)
        else raise WorkflowError, "未知操作: #{type}"
        end

        { ok: true, no: @app.no, status: @app.status,
          statusLabel: STATUS_LABELS[@app.status] || @app.status }
      end

      private

      # ---- 动作 ----

      def submit(_reason)
        gate!(own_application?, '只有申请人本人可以提交')
        gate!(@app.draft?, '草稿状态才能提交')

        @app.update!(status: 'submitted', submitted_at: Time.current)
      end

      def approve_group(_reason)
        gate!(reviewer_authorized?, '仅同团队其他成员可初审')
        gate!(@app.submitted?, '待审批状态才能初审')

        @app.update!(status: 'group_approved',
                     group_reviewer: @user,
                     group_approved_at: Time.current)
      end

      def approve_project(_reason)
        gate!(reviewer_authorized?, '仅同团队其他成员可终审')
        gate!(@app.group_approved?, '小组通过后才能终审')

        @app.update!(status: 'project_approved',
                     project_reviewer: @user,
                     project_approved_at: Time.current)
      end

      def reject(reason)
        gate!(reviewer_authorized?, '仅同团队其他成员可驳回')
        gate!(@app.submitted? || @app.group_approved?, '待审批/小组通过状态才能驳回')

        reviewer_field = @app.submitted? ? :group_reviewer : :project_reviewer
        ts_field = @app.submitted? ? :group_approved_at : :project_approved_at
        note = reason ? "驳回原因：#{reason}" : '驳回原因：（未填写）'

        @app.update!(
          status: 'rejected',
          reviewer_field => @user,
          ts_field => Time.current,
          note: [@app.note.presence, note].compact.join(' | ')
        )
      end

      def complete(_reason)
        gate!(reviewer_authorized?, '仅同团队其他成员可标记完成')
        gate!(@app.project_approved?, '终审通过后才能标记完成')

        @app.update!(status: 'completed', completed_at: Time.current)
      end

      # ---- 闸门 ----

      def gate!(cond, msg)
        raise WorkflowError, msg unless cond
      end

      def own_application?
        @app.requestor_id == @user&.id
      end

      def reviewer_authorized?
        same_team?(@app, @team) && !own_application?
      end

      def same_team?(app, team)
        app.project && app.project.team_id == team&.id
      end

      STATUS_LABELS = {
        'draft'            => '草稿',
        'submitted'        => '待审批',
        'group_approved'   => '小组通过',
        'project_approved' => '已通过',
        'rejected'         => '驳回',
        'completed'        => '已完成'
      }.freeze
    end
  end
end
