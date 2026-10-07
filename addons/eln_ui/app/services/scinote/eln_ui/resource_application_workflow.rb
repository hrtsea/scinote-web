# frozen_string_literal: true

# ELN UI —— 资源申请单写流程（OPEN-10 · REQ-RES-APPLY / REQ-RES-APPROVE）
#
# 状态机（SCN-RES-APPROVE-1~5，二段式审批）：
#   draft --submit--> submitted --approve_group--> group_approved
#         --approve_project--> project_approved --complete--> completed
#   submitted / group_approved --reject--> rejected
#
# 权限闸门口径（★ 唯一真源 = Scinote::ElnUi::ResourceApprovalPolicy，
#   workflow / 详情页 payload / 列表页 payload 三处都去问它，不许再各写一份）：
#   submit          → requestor 本人
#   approve_group   → 该项目「初审」名单内，且非本人
#   approve_project → 该项目「终审」名单内，且非本人
#   reject          → 按当前所处阶段取对应名单（submitted→初审 / group_approved→终审）
#   complete        → 该项目「终审」名单内，且非本人（出库确认由批准执行的人跟进）
#   ⚠ fail-closed：名单为空 = 该阶段无人可批，单据卡在该阶段（ADR-0029 Q2-2）。
#     冷启动出口 = 项目负责人到「资源申请 → 配置审批人」面板按「一键初始化」，
#     把项目负责人写进两阶段名单 —— 不按就真卡住，这是设计，不是 bug。
#
# 驳回溯源（不加列、不动生产表）：复用现有 reviewer 字段记「谁驳的」，
#   submitted 阶段 → group_reviewer；group_approved 阶段 → project_reviewer；
#   驳回原因以「驳回原因：…」前缀追加进 note。
#
# 🔴 材料类 = 请购单（ADR-0030，2026-10-06 用户拍板）：
#   终审通过 → **解锁「到货验收入库」** → 人工验收入库（写侧见 MaterialReceiptPosting）
#   → 单据置 completed。**审批通过本身不碰库存**，也不做出库。
#   出库只由原生任务消耗发生（任务 stock_consumption → RepositoryLedgerRecord →
#   MmrUnitPriceSnapshot decorator 同步 ConsumeRecord）。
#   申请时必填「进入哪个库」(repository_id)；入库时在该库内按名称找/建条目。
#   ⚠ 这里曾按**领用**语义实现过（绑定已存在的 repository_row_id，已删除）——
#     两种语义名字像、方向相反，改动前先读 ADR-0030。
module Scinote
  module ElnUi
    # 继承通用骨架（Scinote::ElnUi::Workflow）：白名单、分派、gate、WorkflowError
    # 都收在基类，这里只留**资源申请单自己的**动作与规则。
    class ResourceApplicationWorkflow < Workflow
      # ⚠ 别名不是重复定义：controller 与 ConsumeRecord 都在 rescue 这个常量，
      #   换成本类定义会让「同一个错」在代码里长成两个类，rescue 就漏了。
      WorkflowError = Scinote::ElnUi::Workflow::WorkflowError

      # ⚠ `complete` 的语义在 ADR-0032 之后变了：它不再是「终审人点一下就入库」，
      #   而是「**验货通过**并按**本批数量**入库」——闸门从终审名单换成了 `receipt` 名单。
      #   另加两个动作：申请人交验货（submit_receipt）、验货人判不通过（reject_receipt）。
      ACTIONS = %w[submit approve_group approve_project reject submit_receipt reject_receipt complete].freeze

      class << self
        def actions
          ACTIONS
        end

        # user/team 由 controller 注入；no = 业务编号；type/reason 来自表单
        #
        # ⚠ `receipt:` 是 ADR-0032 加的**动作专属载荷**（照片附件 id 列表 + 本批数量）。
        #   为什么不在基类 `Workflow#run` 上加 kwargs：基类是
        #   `send(:"apply_#{type}", reason)` 单一位置分派，加了 kwargs 会让**每一个**
        #   动作方法都得接受它（否则 ArgumentError），而 TaskCloseWorkflow 也共用那个基类 ——
        #   为一个流程的专属数据去动共享骨架，代价远大于收益。
        #   这里选择：类方法收下 → 存成实例变量 → 动作按需取。显式、且不外溢。
        def call(user:, team:, no:, type:, reason: nil, receipt: nil)
          app = Scinote::ElnUi::ResourceApplication.find_by(no: no.to_s)
          raise WorkflowError, '申请单不存在' if app.nil?
          # ⚠ 类方法上下文 —— same_team? 是实例私有方法，这里必须内联（本轮 6 errors 根因）
          unless app.project && app.project.team_id == team&.id
            raise WorkflowError, '申请单不属于当前团队'
          end

          new(app: app, user: user, team: team, receipt: receipt).run(type.to_s, reason.to_s.presence)
        end

        # ------------------------------------------------------------
        # 新建申请（SCN-RES-APPLY-1）：表单直建草稿
        #   · 编号自动生成 SQ-YYYY-NNNN（当年前缀下最大序号 + 1；
        #     seed 演示单 SQ-2026-7777 也计入 max，新单会排到 7778 —— 是特性不是 bug）
        #   · 权限：登录团队成员即可发起（审批闸门在实例侧另算）；
        #     项目必须属于当前 team（与 call 的团队口径一致）
        #   · 表单字段：project_id / kind / name / qty / unit / unit_price / purpose
        #     / repository_id（材料类必填）/ my_module_id（选填）
        #     kind 白名单 material | service；qty 必须 > 0；name 必填；
        #     unit / unit_price / purpose 选填（unit_price 空 → 0，详情页显示 ¥0）
        # ------------------------------------------------------------
        # 表单字段逐个显式收进来（不再把 ActionController::Parameters 当参数往下传 ——
        # 服务层不该认识请求对象）；类型不硬转（controller 侧用 permit，见
        # res_apply_create_controller 的踩坑注），这里对 nil / 字符串一律业务判定。
        def create_draft(user:, team:, project_id:, kind:, name:, qty:,
                         unit: nil, unit_price: nil, purpose: nil,
                         service_catalog_id: nil, my_module_id: nil,
                         repository_id: nil)
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

          # 服务类：档案是单价的**唯一来源**（spec V1.21 L986 / L1051）。表单里手填的
          # unit_price 只在 material 上生效；服务申请一律强制选档案条目，并把单价
          # 覆写成档案快照 —— 留一条「手填单价」的路，花费行就再也说不清这 ¥N 从哪来。
          # 服务执行挂在哪个任务下（闸门要靠它反查「这个任务欠了哪些结果」）。
          # 任务必须真属于该项目 —— 挂个别项目的任务，闸门查出来的清单就对不上人。
          my_module_id = my_module_id.to_s.presence
          my_module = nil
          if my_module_id.present?
            my_module = ::MyModule.find_by(id: my_module_id)
            raise WorkflowError, '任务不存在或已归档' if my_module.nil?
            raise WorkflowError, '任务不属于该项目' unless my_module.experiment&.project_id == project.id
          end

          if kind == 'service'
            catalog = ::Scinote::ElnUi::ServiceCatalog.find_by(id: service_catalog_id)
            raise WorkflowError, '服务必须选择测试表征服务档案条目' if catalog.nil?

            unit_price = catalog.snapshot_price
            unit = unit.presence || '次'
          end

          # SCN-RES-TEST-STRIKE-2：未消解占用 ≥ 阈值 → 冻结（只冻**测试表征**，
          #   材料申请照常入 —— 把材料也一起挡了是「一刀切」，spec 明写封禁的对象
          #   是「提交新的测试表征申请」）。管理员可用一次性豁免放行，用后即失效。
          if kind == 'service' && user.present? && ServiceStrikeBook.frozen?(user.id)
            # 冻结了 —— 有未用过的一次性豁免就放行这一次（豁免不消解占用，见 ServiceStrikeBook）。
            # ⚠ 顺序很重要：先判冻结再找豁免，别把豁免当成「没被冻结」的兜底，
            #   否则会出现「占用 0 次也把豁免白白用掉」。
            raise WorkflowError, ServiceStrikeBook.block_reason(user.id) unless ServiceStrikeBook.consume_waiver!(user.id)
          end

          # SCN-RES-RECEIPT-4 的**镜像**：已终审通过但没验完的材料申请 ≥ 阈值 → 冻结
          #   **新建材料申请**（服务类照常入，与上面那条正好互补）。
          #   ⚠ 三步序与豁免都复用服务侧那套（ReceiptPendingBook 内部直接委托
          #     ServiceStrikeBook.consume_waiver!），只换「数什么」。
          #   ⚠ 同一处代码里此时可能有**两重**冻结（服务逾期 + 材料未验货），
          #     而一次豁免只放行其中一处 —— 报错里已说明本次放行的是哪一项。
          if kind == 'material' && user.present? && ReceiptPendingBook.frozen?(user.id)
            raise WorkflowError, ReceiptPendingBook.block_reason(user.id) unless ReceiptPendingBook.consume_waiver!(user.id)
          end

          # ⚠ serviceCatalogId 必须写进 items：登记服务行时靠它回查档案取单价与验收配置。
          #   漏掉这一行 = 每个服务申请都「没绑档案」→ complete 一律 fail-closed 抛错，
          #   整条链路直接走不通（2026-10-06 实测踩到）。
          item = {
            'kind' => kind,
            'name' => name,
            'qty' => json_number(qty),
            'unit' => unit.to_s.strip,
            'unit_price' => json_number(unit_price.presence&.to_d || 0.to_d)
          }
          item['serviceCatalogId'] = catalog.id if kind == 'service'

          # 材料类：**必填「进入哪个库」**（ADR-0030 D7 —— 申请时选定，不留到验收）。
          #   · 绑的是 `Repository`（**库**），不是 `RepositoryRow`（库里的具体条目）。
          #     两者名字像、语义相反：库里已有条目 ⇒ 去领（出库）；料还没进库 ⇒ 请购（入库）。
          #     本流程是**请购**，故只认库；具体条目在【到货验收入库】时按名称找或新建。
          #   · 必须属于本团队：绑到别人团队的库，入库会把料写进别人库房，比「没绑」更糟。
          if kind == 'material'
            raise WorkflowError, '请选择材料进入的目标库' if repository_id.blank?

            repo = ::Repository.find_by(id: repository_id.to_i)
            raise WorkflowError, '目标库不存在' if repo.nil?
            raise WorkflowError, '目标库不属于当前团队' unless repo.team_id == team&.id

            item['repository_id'] = repo.id
          end

          begin
            app = Scinote::ElnUi::ResourceApplication.create!(
              no: next_no!,
              project: project,
              requestor: user,
              status: 'draft',
              note: purpose.to_s.strip.presence,
              item_list: [item],
              # 服务执行归属任务 —— 原生完成闸门靠这一列反查「这个任务欠了哪些结果」
              my_module: my_module
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

      def initialize(app:, user:, team:, receipt: nil)
        @app = app
        # 到货验货物料（照片 + 本批数量）；非验收动作时为 nil，读取方一律给默认值
        @receipt = receipt.is_a?(Hash) ? receipt : {}
        super(user: user, team: team)
      end

      # 基类已提供 run（白名单 → 分派 → result_payload），这里不再重写。

      private

      def result_payload
        { ok: true, no: @app.no, status: @app.status,
          statusLabel: STATUS_LABELS[@app.status] || @app.status }
      end

      # ---- 动作 ----
      # 命名带 apply_ 前缀：基类按白名单拼方法名分派，前缀让「这是状态机的实现」
      # 一眼可见，也避免和实例上别的 apply_* 撞名。

      def apply_submit(_reason)
        gate!(own_application?, '只有申请人本人可以提交')
        gate!(@app.draft?, '草稿状态才能提交')

        @app.update!(status: 'submitted', submitted_at: Time.current)
        # SCN-DASH-7 资源申请结果：提交后通知当前阶段待审批人（配置名单优先）。
        notify_pending_approvers
      end

      def apply_approve_group(_reason)
        gate!(approver_of?('group'), approver_error('group'))
        gate!(@app.submitted?, '待审批状态才能初审')

        @app.update!(status: 'group_approved',
                     group_reviewer: @user,
                     group_approved_at: Time.current)
        notify_requestor('已通过小组初审')
      end

      def apply_approve_project(_reason)
        gate!(approver_of?('project'), approver_error('project'))
        gate!(@app.group_approved?, '小组通过后才能终审')

        @app.update!(status: 'project_approved',
                     project_reviewer: @user,
                     project_approved_at: Time.current)
        notify_requestor('已通过终审')
      end

      def apply_reject(reason)
        # 驳回按**当前所处的阶段**取名单：submitted 用初审名单、group_approved 用终审名单。
        # ⚠ 不能用「任一阶段」取并集 —— 那就是把两个阶段的资格混成一个宽口径，
        #   配初审人的人等于顺手把终审权也给了出去。
        stage = Scinote::ElnUi::ResourceApprovalPolicy.pending_stage(@app)
        gate!(stage.present? && approver_of?(stage), approver_error(stage || 'group'))
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
        notify_requestor('被驳回', reason: reason)
      end

      # ---- 到货验收（REQ-RES-RECEIPT / ADR-0032）----
      #
      # 三个动作把「终审通过」到「已入库」之间那段拆开：
      #   submit_receipt（申请人）→ 建一条**待验**记录（照片 + 本批数量）
      #   complete（验货人）    → 按本批数量入库，累计达标才收口
      #   reject_receipt（验货人）→ 记录不通过并**退回待审批**，记录与照片保留

      # 申请人提交本批验收。
      # ⚠ 照片必传（SCN-RES-RECEIPT-1）：`@receipt[:photos]` 是 controller 传进来的
      #   **已挂载到本记录上的附件**（controller 先建记录再 attach，见 res_apply_receipt_controller），
      #   这里只校验「至少一张」—— 上传动作本身在 controller 层，不塞进状态机。
      def apply_submit_receipt(reason = nil)
        photos = @receipt[:photos] || []
        batch = @receipt[:qty].to_d

        gate!(own_application?, '只有申请人本人可以提交到货验收')
        gate!(@app.material?, '服务类申请不经过到货验收（服务不建库存）')
        gate!(@app.project_approved?, '终审通过后才能提交到货验收')
        gate!(photos.present?, '请先上传到货照片（照片是入库的前置证据）')
        gate!(batch.positive?, '请填写本批到货数量（必须大于 0）')
        # 同一张单同时只允许一条「待验」记录：两个人同时提交会让「这批是多少」变成两笔。
        gate!(Scinote::ElnUi::ReceiptVerification.open_for(@app).empty?,
              '本单已有待验货记录，请等验货人处理后再提交下一批')

        v = Scinote::ElnUi::ReceiptVerification.create!(
          resource_application: @app, status: 'pending', qty: batch,
          note: reason.presence, created_by: @user
        )
        # 挂照片在记录建好之后：ActiveStorage 的 attach 需要记录已有 id
        Array(photos).each { |p| attach_photo(v, p) }
        v
      end

      # 把一张照片挂到验收记录上。
      # ⚠ 接受四种形态，因为上传链路的入口不止一个：
      #   · Hash（io/filename/content_type）—— 控制器直接给哈希；
      #   · ActionDispatch::Http::UploadedFile —— 浏览器 multipart 上传（**主路径**，
      #     有 original_filename/content_type，ActiveStorage 不认这个对象本身，
      #     必须显式拆成 io/filename/content_type）；
      #   · 已上传的附件 id（Integer/String）—— 前端先传 id 上来；
      #   · 任何 respond_to?(:read) 的上传结果对象。
      #   不认识的形态**不静默跳过**：照片挂不上而记录仍标成「已验货」，
      #   正是 SCN-RES-RECEIPT-1 要禁的形态（凭证缺了却流转下去）。
      def attach_photo(verification, photo)
        case photo
        when Hash
          verification.photos.attach(**photo.symbolize_keys)
        when Integer, String
          att = ActiveStorage::Attachment.find_by(id: photo.to_s)
          verification.photos << att if att
        else
          if photo.respond_to?(:original_filename)
            verification.photos.attach(io: photo, filename: photo.original_filename,
                                      content_type: photo.try(:content_type))
          elsif photo.respond_to?(:read) || photo.respond_to?(:to_io)
            verification.photos.attach(photo)
          end
        end
      rescue StandardError => e
        # ⚠ 附件系统级故障不吞：吞掉会静默产出「无照片的已验货记录」。
        raise WorkflowError, "到货照片挂载失败：#{e.message}"
      end

      # 验货人判不通过：记录留痕 + 退回「待审批」重走两级审批。
      # ⚠ 记录**不删**（审计凭据，SCN-RES-RECEIPT-4/ADR-0032 的「历史轮次保留」）；
      #   申请人补货后重走审批，届时可再提交新一轮验收。
      def apply_reject_receipt(reason = nil)
        gate!(verifier_of?, verifier_error)
        gate!(@app.material?, '服务类申请不经过到货验收')
        gate!(@app.project_approved?, '终审通过后才能验货')

        open = Scinote::ElnUi::ReceiptVerification.open_for(@app).first
        gate!(open.present?, '没有待验货记录可判不通过')

        why = reason.to_s.strip
        gate!(why.present?, '请填写验货不通过的理由（申请人要靠它补货）')

        open.update!(status: 'rejected', verifier: @user, verified_at: Time.current, rejection_reason: why)
        @app.update!(status: 'submitted', note: [@app.note.presence, "验货不通过：#{why}"].compact.join(' | '))
        notify_requestor('到货验收不通过', reason: why)
      end

      def verifier_of?
        Scinote::ElnUi::ResourceApprovalPolicy.can_verify_receipt?(
          user: @user, application: @app, team: @team
        )
      end

      def verifier_error
        '本项目的验货人名单里没有你（或该项目不允许自验），无法验货。' \
          '请让项目负责人配置「验货」阶段审批人名单'
      end

      # ---- 通知（SCN-DASH-7 资源申请结果）----
      # 申请结果一律通知申请人；提交动作通知项目待审人（项目负责人）。
      # 通知是副作用，发布失败不影响审批主流程（见 NotificationPublisher 的 fail-soft）。

      def notify_requestor(verb, reason: nil)
        title = "资源申请 #{@app.no} #{verb}"
        msg = "您提交的资源申请 #{@app.no} #{verb}" \
              "#{reason.present? ? '：' + reason : ''}。"
        Scinote::ElnUi::NotificationPublisher.notify(
          @app.requestor, title: title, message: msg, subject: @app
        )
      end

      # 提交 → 通知**当前阶段真能批的人**（初审名单）。
      # ⚠ 名单为空时回落到项目负责人，这里是**刻意的**不对称：
      #   放行必须 fail-closed（没人能批就是没人能批，单据卡住是显式信号）；
      #   但通知 fail-closed 会让这张单子在黑暗里躺着 —— 没人知道自己在等。
      #   多通知一个人不产生任何越权，所以通知侧宁宽不宁漏。
      def notify_pending_approvers
        stage = Scinote::ElnUi::ResourceApprovalPolicy.pending_stage(@app) || 'group'
        targets = Scinote::ElnUi::ResourceApprovalPolicy.approvers(@app.project, stage)
        targets = Scinote::ElnUi::NotificationPublisher.project_owners(@app.project) if targets.empty?
        return if targets.empty?

        title = "有新的资源申请待审批 #{@app.no}"
        msg = "申请人 #{@app.requestor&.name} 提交了资源申请 #{@app.no}，请审核。"
        targets.uniq(&:id).each do |target|
          Scinote::ElnUi::NotificationPublisher.notify(
            target, title: title, message: msg, subject: @app
          )
        end
      end

      # 🔴 材料类走这里 = **到货验收入库**（ADR-0030 D2），不是「标记完成」，更不是出库。
      #   出库只由任务消耗发生（D4），本动作**不**扣减任何库存。
      #   动作 key 仍叫 `complete`（前端与既有测试都按这个名字调的），但语义与文案已变；
      #   spec 里「标记完成（出库确认）」（L1161）那句要一并改写。
      # ⚠ **ADR-0032 修正了 ADR-0030 的此项**：材料类的闸门从「终审名单」换成「`receipt` 验货名单」。
      #   原来判 `approver_of?('project')`（终审人点一下就入库），那样「谁验货」不可配置、
      #   且入库前没有任何证据。取名沿用 `complete` 是为了不动前端/控制器/既有测试的调用面。
      #
      # 🔴⚠ **材料与服务必须各走各的闸门**，别把验货闸门提到分支外面：
      #   `can_verify_receipt?` 对服务类**恒 false**（服务不建库存、不经历货），
      #   提到前面会让**服务申请永远完不成**（实测 22 个 error 全是这一条）。
      #   spec V1.21 / SCN-RES-APPROVE-4：服务类「审批通过即获执行许可」，
      #   完成动作仍由**终审人**执行 —— 那条口径没有被 ADR-0032 动过。
      def apply_complete(_reason)
        # ⚠ 顺序：先判「已完成」再判阶段。反过来的话，已完成的单子会命中
        #   「终审通过后才能…」——对用户是误导（他明明已经通过了），真正的原因是不能重复入库。
        gate!(!@app.completed?, '该申请已完成，不能重复入库')

        if @app.material?
          gate!(verifier_of?, verifier_error)
          gate!(@app.project_approved?, '终审通过后才能执行验货入库')

          # 分批（ADR-0032 D5）：入库数量取**本条待验记录**的 qty，不再取整单量。
          # ⚠ 没有待验记录就不许入库 —— 照片与本批数量是入库的前置证据（SCN-RES-RECEIPT-1）。
          open = Scinote::ElnUi::ReceiptVerification.open_for(@app).first
          gate!(open.present?, '没有待验货记录：请先让申请人提交到货照片与本批数量')
          gate!(open.qty.to_d.positive?, '本批到货数量必须大于 0')

          # ⚠ 状态与「库存写侧」必须在同一事务里：要么「已完成 + 库存已进」，要么原地不动。
          #   拆成两次写就会出现「单子已完成但库里没这批料」的漂移，而这种漂移**看不见**。
          # ⚠ requires_new: true 的理由见下方原注释（minitest 事务化夹具下，不带 savepoint
          #   会把回滚推迟到最外层，断言「状态没被带成 completed」就成了假断言）。
          @app.transaction(requires_new: true) do
            receive_material!(batch_qty: open.qty.to_d, verifier: @user, verification: open)
          end
        else
          # 服务类：服务不建库存、不入额度（V1.21 / SCN-RES-APPROVE-4），
          # 终审通过即获执行许可，执行完成在明细表登记服务行。
          gate!(approver_of?('project'), approver_error('project'))
          gate!(@app.project_approved?, '终审通过后才能执行服务')

          @app.transaction(requires_new: true) do
            @app.update!(status: 'completed', completed_at: Time.current)
            Scinote::ElnUi::ConsumeRecord.sync_service_from_application!(
              app: @app, occurred_at: @app.completed_at
            )
          end
        end
      end

      # 到货验收入库：写侧收口在 MaterialReceiptPosting（建/累加条目与 Stock）。
      # 失败一律转成 WorkflowError —— controller 只 rescue 这一个常量，
      # 让 PostingError 漏出去就是 500，而它其实是**用户可读的业务失败**
      # （比如「目标库未配置库存列」）。
      def receive_material!(batch_qty: nil, verifier: nil, verification: nil)
        result = Scinote::ElnUi::MaterialReceiptPosting.call(
          application: @app, user: verifier || @user, qty: batch_qty
        )
        @app.record_receipt!(result[:row].id)

        # ⚠ 必须**先**把这条待验记录标成 passed，再判累计达标：
        #   否则 verified_qty 少算这一批，累计永远差一口 → 单子收不了口（死循环）。
        verification&.update!(status: 'passed', verifier: verifier || @user, verified_at: Time.current)

        # 分批收口（ADR-0032 D7 / SCN-RES-RECEIPT-3）：库房数字说话 ——
        # 累计已验 ≥ 申请量才置「已完成」；未达标**留在 project_approved** 等下一批，
        # 那是正常态不是异常。单靠状态位区分「待第一验」与「验过一批还有下一批」，
        # 免掉一个「这是最后一批吗」的易漏勾选。
        done = Scinote::ElnUi::ReceiptVerification.completed_threshold_reached?(@app.reload)
        @app.update!(status: done ? 'completed' : 'project_approved',
                     completed_at: (Time.current if done))
      rescue Scinote::ElnUi::MaterialReceiptPosting::PostingError => e
        raise WorkflowError, e.message
      end

      # ---- 闸门（gate! 由基类提供）----

      def own_application?
        @app.requestor_id == @user&.id
      end

      # ★ 审批闸门一律问 Scinote::ElnUi::ResourceApprovalPolicy —— 详情页、
      #   列表页、本闸门三处同一句话写在三个地方，就是「按钮可见 / 点下去 422」的老病。
      #   fail-closed：名单里没有这个人 = 不能批，没有第二条路径。
      def approver_of?(stage)
        Scinote::ElnUi::ResourceApprovalPolicy.can_approve?(
          user: @user, application: @app, stage: stage, team: @team
        )
      end

      # 被挡下来时给出的理由必须**可行动**：告诉他是没配人还是他不在名单里，
      # 「无权操作」这种话用户只能去问开发。
      def approver_error(stage)
        # ⚠ 自审已放开（申请人可配为审批人后审批自己的单）—— 不再有「本人不可审」分支。
        #   挡下来的原因只剩两种：阶段未配人 / 不在名单内，都给可直接行动的话。
        label = Scinote::ElnUi::ProjectApprover.stage_labels[stage.to_s] || stage.to_s
        return "该项目未配置#{label}人，请联系项目负责人配置后再审批" \
          unless Scinote::ElnUi::ResourceApprovalPolicy.configured?(@app.project, stage)

        "您不在该项目的#{label}人名单内"
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
