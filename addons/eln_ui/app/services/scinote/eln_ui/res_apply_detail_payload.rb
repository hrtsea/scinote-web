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
          # 关联出入库记录：**本单入库后**在目标库里落到的那个条目 → 它的原生任务消耗流水。
          # 未入库（还没收货）⇒ 空数组是**正确**结果：那时条目还不存在，自然没有消耗可言。
          linkedConsumptions: linked_consumptions_block(app),
          # ⚠ 位置：**顶层**，不塞进 approvals。踩过一次：原先它写在 approvals 里，
          #   而前端按顶层读 ⇒ 取不到 ⇒ 静默回落成「已验 0 / 共 0」（2026-10-06 实测）。
          #   教训：payload 的**层级**也是契约的一部分，后端加键位置与前端取值必须一起改。
          #   语义上它也不是「权限位」，是验货进度 —— 归 approvals 本就不合适。
          receiptProgress: receipt_progress_block(app),
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
          myModule: app.my_module ? { id: app.my_module_id, name: app.my_module.name.to_s } : nil,
          # 材料类：目标库（申请时选定）。服务类恒 nil（服务不建库存，V1.21）。
          targetRepository: target_repository_block(app),
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
          # 🔴 两个 id 语义相反，别混（ADR-0030）：
          #   targetRepositoryId     = 目标**库**，申请时选定（请购：料还没进库）
          #   receivedRepositoryRowId = 入库后实际落到的**条目**，由 MaterialReceiptPosting 写回；
          #                            入库前恒 nil —— 因为那时条目根本还不存在。
          #   上一版这里是 `repositoryRowId`（申请时绑一条**已存在**的条目，领用语义），已删。
          repo_id = it['repository_id'] || it[:repository_id]
          received_row_id = it['received_repository_row_id'] || it[:received_repository_row_id]
          {
            kind: kind,
            kindLabel: kind == 'service' ? '测试表征' : '材料',
            name: (it['name'] || it[:name]).to_s,
            qty: "#{qty} #{unit}".strip,
            qtyRaw: qty,
            unit: unit,
            unitPrice: format_money(unit_price),
            amount: format_money(qty * unit_price),
            targetRepositoryId: repo_id,
            targetRepositoryName: repository_name(repo_id),
            receivedRepositoryRowId: received_row_id,
            receivedRepositoryRowName: repository_row_name(received_row_id)
          }
        end
      end

      # 库名 —— 取不到（未选 / 已删）一律 nil，不回落占位文案。
      def repository_name(repo_id)
        return nil if repo_id.blank?

        ::Repository.find_by(id: repo_id.to_i)&.name&.to_s
      end

      # 目标库整块 —— 详情页顶部要一眼看到「这单的料会进哪个库」。
      def target_repository_block(app)
        repo_id = app.repository_id
        return nil if repo_id.blank?

        repo = ::Repository.find_by(id: repo_id.to_i)
        return nil if repo.nil?

        { id: repo.id, name: repo.name.to_s }
      end

      # 绑定的库存条目名 —— 取不到（未绑 / 已删）一律 nil，不回落占位文案。
      def repository_row_name(row_id)
        return nil if row_id.blank?

        ::RepositoryRow.find_by(id: row_id.to_i)&.name&.to_s
      end

      # 关联出入库/消耗记录：定位**本单**的出库动作，再取同步来的 ConsumeRecord。
      #
      # 🔴 溯源起点是 `received_repository_row_id`（**入库时**写回的实际条目），
      #   不是申请时选的库：同一库里同名条目会被复用/累加，只拿库当起点等于把整个库
      #   的流水都算进来。没有这个 id（还没入库）→ 返回空，**不是** bug。
      #
      # 口径分两档（越靠前越精确）：
      #   ① 有绑定任务 → 只认「该任务 × 该条目」的消耗流水（reference_id ∈ 这些 MMR）。
      #      只按条目反查是不够的：同一种料被多个任务领用是常态，
      #      那样会把**别人任务的消耗**算到本单头上（2026-10-06 在乙醇上实测到这条噪声）。
      #   ② 没绑任务（历史数据）→ 退回按 StockValue（EAV: cell.repository_row_id）反查，
      #      有得看总比没有强，但语义上已经是「这条料上的全部消耗」。
      #   ③ 都没 → 空数组。
      #
      # 只反查、不写库。
      def linked_consumptions_block(app)
        row_id = app.received_repository_row_id
        return [] if row_id.nil?

        ledger_ids = linked_ledger_ids(app, row_id)
        return [] if ledger_ids.empty?

        ::Scinote::ElnUi::ConsumeRecord
          .where(source_type: 'RepositoryLedgerRecord', source_id: ledger_ids)
          .order(occurred_at: :desc)
          .map { |r| consume_row(r) }
      end

      def linked_ledger_ids(app, row_id)
        scope = ::RepositoryLedgerRecord.where(reference_type: 'MyModuleRepositoryRow')

        mmr_ids = if app.my_module_id.present?
                    ::MyModuleRepositoryRow
                      .where(my_module_id: app.my_module_id, repository_row_id: row_id)
                      .pluck(:id)
                  end

        if mmr_ids
          return [] if mmr_ids.empty?

          scope.where(reference_id: mmr_ids).pluck(:id)
        else
          stock_value_ids = ::RepositoryStockValue
                             .joins(:repository_cell)
                             .where(repository_cells: { repository_row_id: row_id })
                             .pluck(:id)
          return [] if stock_value_ids.empty?

          scope.where(repository_stock_value_id: stock_value_ids).pluck(:id)
        end
      end

      def consume_row(r)
        {
          id: r.id,
          name: r.name.to_s,
          qty: "#{r.quantity} #{r.unit}".strip,
          amount: format_money(r.amount),
          occurredAt: dt(r.occurred_at),
          resultStatus: r.result_status
        }
      end

      def timeline_block(app)
        events = []
        events << { key: 'created',   at: dt(app.created_at),         label: '创建申请', by: user_block(app.requestor) } if app.created_at
        events << { key: 'submitted', at: dt(app.submitted_at),       label: '提交审批', by: user_block(app.requestor) } if app.submitted_at
        events << { key: 'group',     at: dt(app.group_approved_at),  label: '小组通过', by: user_block(app.group_reviewer) }  if app.group_approved_at
        events << { key: 'project',   at: dt(app.project_approved_at),label: '项目通过', by: user_block(app.project_reviewer) } if app.project_approved_at
        # 材料类走「到货验收入库」，服务类走「执行完成登记」——同一个终态，两个说法。
        # 写死「已出库」会让材料单显示错（入库≠出库，方向相反），见 ADR-0030。
        events << { key: 'completed', at: dt(app.completed_at),
                    label: app.material? ? '已验收入库' : '已完成', by: nil } if app.completed_at
        events << { key: 'rejected',  at: nil, label: '已驳回', by: nil } if app.rejected?
        events
      end

      # ⚠ 「能点哪个按钮」只有一个答案来源 —— ResourceApprovalPolicy.available_actions。
      #   这里再判一遍与否�� equals 不是第二道保险，是第二个口径。
      def approvals_block(app)
        actions = Scinote::ElnUi::ResourceApprovalPolicy.available_actions(
          user: @user, application: app, team: @team
        )
        {
          groupRequired:  app.submitted?,
          projectRequired: app.group_approved?,
          canApproveGroup:  actions.include?('approve_group'),
          canApproveProject: actions.include?('approve_project'),
          canReject: actions.include?('reject'),
          canComplete: actions.include?('complete'),
          # ---- 到货验收（REQ-RES-RECEIPT / ADR-0032）----
          # ⚠ 这三个键**不**来自 available_actions —— available_actions 回答的是
          #   「审批谁能做什么」，而验货是**申请人交照片** + **验货人判定**两个不同主体，
          #   硬塞进同一份动词表会把「谁能验」与「谁能批」混成一个口径。
          #   判据仍然是同一个闸门 ResourceApprovalPolicy#can_verify_receipt?，不新增第二套。
          canSubmitReceipt: can_submit_receipt?(app),
          canVerifyReceipt:  can_verify_receipt?(app),
          canRejectReceipt:  can_verify_receipt?(app) && Scinote::ElnUi::ReceiptVerification.open_for(app).any?,
          # 不能操作时给一句可行动的话（名单没配 / 不在名单内），别只让按钮消失
          hint: approval_hint(app, actions)
        }
      end

      # 申请人可交验收：本人 + 材料类 + 已终审通过 + 当前没有待验记录
      def can_submit_receipt?(app)
        return false unless app.material? && app.project_approved?
        return false unless app.requestor_id == @user.id

        Scinote::ElnUi::ReceiptVerification.open_for(app).empty?
      end

      # ⚠ 必须**同时**判状态：policy 只答「谁有资格验」，不答「现在是不是验货阶段」。
      #   漏掉状态判定的症状：在 `group_approved`（刚过初审、还没终审）的单上，
      #   验货人**照样看到「验货通过并入库」按钮**，点了必被 422 ——
      #   与当初 `complete` 那个「显示点了必被拒的按钮」是同一类错（2026-10-06 实测）。
      def can_verify_receipt?(app)
        return false unless app.project_approved?

        Scinote::ElnUi::ResourceApprovalPolicy.can_verify_receipt?(
          user: @user, application: app, team: @team
        )
      end

      # 分批验收进度 + 逐轮记录（照片给前端渲染缩略图）
      def receipt_progress_block(app)
        rv = Scinote::ElnUi::ReceiptVerification
        {
          appliedQty: rv.applied_qty(app).to_s,
          verifiedQty: rv.verified_qty(app).to_s,
          rounds: rv.for_application(app).order(:created_at).map do |v|
            {
              id: v.id,
              status: v.status,
              statusLabel: v.status_label,
              qty: v.qty.to_s,
              note: v.note,
              rejectionReason: v.rejection_reason,
              # ⚠ 人名一律走 `full_name.presence || email`（与本文件 :92 的既有写法同款）——
              #   别顺手写个 display_name：本类没有那个方法（它在 ResCenterPayload 里），
              #   复制调用会得到 NoMethodError（实测踩过）。
              verifier: v.verifier ? (v.verifier.full_name.presence || v.verifier.email).to_s : nil,
              verifiedAt: v.verified_at ? v.verified_at.strftime('%Y-%m-%d %H:%M') : nil,
              # 照片只给 id + 文件名：真实字节走宿主附件路由，前端不直接吃 blob
              photos: v.photos.map { |ph| { id: ph.id, filename: ph.filename.to_s } }
            }
          end
        }
      end

      def approval_hint(app, actions)
        return nil if actions.any?
        # ⚠ 材料类停在「已终审通过」时，卡住它的是**验货**阶段而不是终审 ——
        #   hint 指错阶段会把人引到「配置终审人」上去，而那儿已经配好了（正是它放行的）。
        return receipt_hint(app) if app.material? && app.project_approved?

        stage = Scinote::ElnUi::ResourceApprovalPolicy.pending_stage(app)
        stage = 'project' if stage.nil? && app.group_approved?
        return nil if stage.nil?

        label = Scinote::ElnUi::ProjectApprover.stage_labels[stage] || stage
        unless Scinote::ElnUi::ResourceApprovalPolicy.configured?(app.project, stage)
          return "该项目未配置#{label}人，请联系项目负责人配置后再审批"
        end

        "您不在该项目的#{label}人名单内"
      end

      # 到货验收阶段的提示：区分「没配验货人」与「不在名单内」两种原因，
      # 并把「等申请人交照片」也说出来 —— 那是**正常的中间态**，不该被当成出错。
      def receipt_hint(app)
        open = Scinote::ElnUi::ReceiptVerification.open_for(app)
        if open.any?
          return nil if app.requestor_id == @user.id    # 申请人自己在等，不该被提示打扰
          return "等申请人提交到货照片与本批数量后由验货人判定"
        end
        return '待申请人提交到货照片与本批数量' if app.requestor_id == @user.id

        unless Scinote::ElnUi::ResourceApprovalPolicy.configured?(app.project, 'receipt')
          return '该项目未配置验货人，请联系项目负责人配置「验货」阶段名单'
        end

        '您不在该项目的验货人名单内'
      end

      # policy 的阶段名是字符串 'group' / 'project'，详情页历史调用传的是符号 :group；
      # 这里一次性对齐，别让两种写法在同一个文件里流通。
      def can_approve?(app, level)
        Scinote::ElnUi::ResourceApprovalPolicy.can_approve?(
          user: @user, application: app, stage: level.to_s, team: @team
        )
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
          # 终审通过 → **到货验收入库**（ADR-0030 D2）：终审只**解锁**验收，
          #   真正把料写进库存的是这个人工动作。它**不**做出库（出库只由任务消耗发生，D4）。
          # ⚠ 与审批同源：终审名单里的人才能验收。
          canComplete: Scinote::ElnUi::ResourceApprovalPolicy.can_approve?(
            user: @user, application: app, stage: 'project', team: @team
          ) && app.project_approved?,
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
