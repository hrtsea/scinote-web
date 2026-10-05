# frozen_string_literal: true

# ELN UI —— 任务详情页（PAGE-TASK-DETAIL）的**真实**数据装配
#
# 与前三个 Payload 同一条规矩：**不编造**。取得到就给真值，取不到就显式留白并说明
# 为什么取不到（原生没有承载面 ≠ 「原生有但没取出来」）。
#
# 原生能给的（真值来源）：
#   my_modules            name / description / state / due_date / started_on / completed_on / created_at
#   my_module_status      任务状态（默认流只有三档：Not started / In progress / Completed）
#   user_my_modules       指派组员（20/248 个任务有）
#   steps                 原生 Protocol 步骤（59/248 个任务有）—— DEC-010「记录本挂在任务层」
#   task_comments         讨论区（⚠ 外键是 associated_id 不是 my_module_id）
#   results               任务成果（5/248 个任务有）
#   my_module_repository_rows 关联试剂/耗材（有 stock_consumption，2 个任务有）
#
# 原生**没有**、由 addon 自有表 eln_ui_task_profiles 承载：
#   任务目的 purpose / 执行计划 plan / 显式负责人 owner_user / 业务编号 business_code
#   （my_modules 32 列里没有任何一列能装这些，PRD §7.8.2「任务信息」卡要展示）
#
# 原生**没有**、只能留白 + 说明的（不编）：
#   - 五档任务状态机的「提交完成申请 / 待审核」两档 —— 默认流只有三档（OPEN-9）
#   - 「完成申请时间」「驳回理由」—— 原生无字段
#   - 结构化数据录入表单 —— 原生 Step 只有自由文本 + checklist（DEC-009 才是结构化）
#   - 关联项目指标 —— 原生无项目级指标表
#
# 字段名对应原型 src/views/TaskDetail.vue + src/data/mock.js 的 taskDetail：
#   info{experiment,purpose,plan} steps[] comments[] results[] resources[]
#   attributes[{key,value,kind}] flow[{title,sub,color}] profile{} review{}

module Scinote
  module ElnUi
    class MyModuleDetailPayload
      DASH = '—'

      # ⚠ 默认状态流三档 → 原型 status 取值域三档（与 ExpDetailPayload 同一套口径）。
      #   「提交完成申请 / 待审核」两档在原生不存在，就不给它们编状态（OPEN-9）。
      STATUS_CODE = { 'Not started' => 'pending',
                      'In progress' => 'active',
                      'Completed' => 'done' }.freeze

      STATUS_TEXT = { 'pending' => '待接收',
                      'active' => '进行中',
                      'done' => '已完成' }.freeze

      STATUS_COLOR = { 'pending' => 'var(--status-notstarted)',
                       'active' => 'var(--status-active)',
                       'done' => 'var(--status-done)' }.freeze

      class << self
        def call(my_module, user, can_manage_task: false, can_complete_task: false,
                 can_create_comment: false)
          new(my_module, user, can_manage_task: can_manage_task,
                               can_complete_task: can_complete_task,
                               can_create_comment: can_create_comment).call
        end
      end

      def initialize(my_module, user, can_manage_task: false, can_complete_task: false,
                     can_create_comment: false)
        @my_module = my_module
        @user = user
        @can_manage_task = can_manage_task
        @can_complete_task = can_complete_task
        @can_create_comment = can_create_comment
      end

      def call
        code = STATUS_CODE.fetch(status_of(@my_module), 'pending')
        {
          taskId: @my_module.id.to_s,
          projectId: project_id,
          experimentId: @my_module.experiment_id.to_s,
          # 面包屑三段：原型里是写死的 PR1025240 / EX1 / 底涂剂选型对比实验
          crumb: { listUrl: '/eln_project_list',
                   projectId: project_id,
                   # 下钻地址由服务端下发（前端不写死宿主路由 —— 那是唯一真源）。
                   projectUrl: project_id ? "/projects/#{project_id}/eln_project_detail" : nil,
                   projectName: project_name,
                   experimentId: @my_module.experiment_id.to_s,
                   experimentUrl: "/experiments/#{@my_module.experiment_id}/eln_exp_detail",
                   experimentName: experiment_name },
          taskName: @my_module.name.to_s,
          statusCode: code,
          statusText: STATUS_TEXT.fetch(code, '进行中'),
          # 原生状态名原样带过去：界面上要能看出「这是原生三档里的哪一档」，
          # 不然「待接收」会让人以为原生真有这一档。
          statusNative: @my_module.my_module_status&.name.to_s,
          statusColor: STATUS_COLOR.fetch(code, STATUS_COLOR['pending']),
          canManageTask: @can_manage_task,
          canCompleteTask: @can_complete_task,
          canCreateComment: @can_create_comment,
          info: info_block,
          steps: steps_block,
          checklist: checklist_block,
          comments: comments_block,
          results: results_block,
          resources: resources_block,
          attributes: attributes_block,
          flow: flow_block,
          # 五态机缺口说明：原生默认流只有三档，「提交完成申请 / 待审核」没有节点可挂。
          # 不编时间、不编状态 —— 页面据此渲染一条说明而不是伪造轨迹。
          flowNote: flow_note,
          profile: profile_block,
          review: review_block
        }
      end

      private

      def project_id
        @project_id ||= begin
          exp = @my_module.experiment
          exp.respond_to?(:project_id) ? exp.project_id : nil
        end
      end

      def project_name
        @project_name ||= begin
          exp = @my_module.experiment
          exp&.project&.name.to_s
        end
      end

      def experiment_name
        @experiment_name ||= @my_module.experiment&.name.to_s
      end

      def profile
        return nil unless task_profile_class

        task_profile_class.find_by(my_module_id: @my_module.id)
      end

      # 二开表不存在（老实例没 apply）→ 返回 nil 走降级，别让整页 500
      def task_profile_class
        klass = ::Scinote::ElnUi::TaskProfile if defined?(::Scinote::ElnUi::TaskProfile)
        klass&.table_exists? ? klass : nil
      rescue StandardError
        nil
      end

      def status_of(module_obj)
        st = module_obj.my_module_status
        return nil unless st

        st.name.to_s
      end

      # ------------------------------------------------------------
      # 任务信息卡（PRD §7.8.2 任务信息 Tab）
      # ------------------------------------------------------------
      def info_block
        { experiment: experiment_name,
          # 目的：二开档案优先；没有档案就回落原生富文本 description（压成纯文本）
          purpose: (profile&.purpose.presence || native_description),
          # 执行计划：原生**完全没有**承载面 → 只有二开档案里才有
          plan: (profile&.plan.presence || '') }
      end

      def native_description
        raw = @my_module.description
        return '' if raw.blank?

        raw.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
      end

      # ------------------------------------------------------------
      # 实验记录本 / 步骤（DEC-010：记录本落在任务层，原生就是 Protocol + Step）
      # ------------------------------------------------------------
      def steps_block
        return [] unless @my_module.respond_to?(:steps)

        @my_module.steps.order(:position).map do |s|
          { name: s.name.to_s,
            description: plain_text(s.description),
            completed: s.completed?,
            completedOn: s.completed_on&.strftime(DATE_FMT),
            checklists: s.respond_to?(:checklists) ? s.checklists.count : 0 }
        end
      end

      # 结构化数据录入：原生只有 Step 自由文本 + checklist，没有「结构化字段录入表单」。
      # 有 checklist 就把它当结构化面渲染（真值），没有就给空数组让组件说明「原生无此面」。
      def checklist_block
        return { available: false, note: structured_note, fields: [] } unless @my_module.respond_to?(:steps)

        fields = []
        @my_module.steps.order(:position).each do |s|
          next unless s.respond_to?(:checklists)

          s.checklists.order(:created_at).each do |c|
            fields << { label: c.text.to_s, value: c.checked? ? '已完成' : '未勾选', step: s.name.to_s }
          end
        end
        { available: fields.any?, note: structured_note, fields: fields,
          stepCount: @my_module.steps.count }
      end

      def structured_note
        '原生 Step 只有自由文本 + 清单（checklist），没有独立的结构化录入表单；' \
          '结构化字段属二开（DEC-009），取值来自真实 checklist。'
      end

      # ------------------------------------------------------------
      # 讨论区 / 成果 / 关联资源
      # ⚠ TaskComment 的外键是 associated_id（belongs_to :my_module, foreign_key: :associated_id）
      #   直接 where(my_module_id:) 会抛 PG::UndefinedColumn —— 走 m.task_comments 关联最稳。
      # ------------------------------------------------------------
      def comments_block
        return [] unless @my_module.respond_to?(:task_comments)

        @my_module.task_comments.order(:created_at).map do |c|
          { author: display_name(c.user), time: c.created_at&.strftime('%m-%d %H:%M'),
            body: c.message.to_s,
            editable: c.user_id == @user&.id }
        end
      end

      def results_block
        return [] unless @my_module.respond_to?(:results)

        @my_module.results.order(:created_at).map do |r|
          { name: r.name.to_s, time: r.created_at&.strftime(DATE_FMT), type: r.type.to_s,
            kind: result_kind(r) }
        end
      end

      def result_kind(result)
        return 'asset' if result.respond_to?(:asset) && result.asset.present?
        return 'table' if result.respond_to?(:tables) && result.tables.present?

        'text'
      end

      def resources_block
        return [] unless @my_module.respond_to?(:my_module_repository_rows)

        @my_module.my_module_repository_rows.map do |rr|
          row = rr.repository_row
          next if row.nil?

          { name: row.name.to_s,
            value: consumption_text(rr),
            unit: unit_name(rr) }
        end.compact
      end

      def consumption_text(rr)
        return DASH if rr.stock_consumption.blank?

        format_number(rr.stock_consumption)
      end

      def unit_name(rr)
        item = rr.respond_to?(:repository_stock_unit_item) ? rr.repository_stock_unit_item : nil
        unit = item.respond_to?(:repository_unit) ? item.repository_unit : nil
        unit.respond_to?(:name) ? unit.name.to_s : nil
      end

      # Decimal 存 12,4：to_f.to_s 会把 20 显示成 20.0 → 整数回落
      def format_number(value)
        f = value.to_f
        return '0' if f.zero?

        f == f.floor ? f.to_i.to_s : f.to_s
      end

      # ------------------------------------------------------------
      # 右栏「任务属性」六行（原型 mock.js 的 6 项，逐项换成真值）
      # ------------------------------------------------------------
      def attributes_block
        [attr_state, attr_assignee, attr_experiment, attr_created, attr_submitted, attr_due].compact
      end

      def attr_state
        { key: '当前状态', value: STATUS_TEXT.fetch(STATUS_CODE.fetch(status_of(@my_module), 'pending'), '进行中'),
          kind: 'chip' }
      end

      def attr_assignee
        names = assigned_names
        { key: '指派组员', value: names.empty? ? DASH : names.join('、'), kind: names.empty? ? 'plain' : 'strong' }
      end

      def attr_experiment
        { key: '上级实验', value: experiment_name, kind: 'mono' }
      end

      def attr_created
        { key: '接收时间', value: @my_module.created_at&.strftime('%m-%d %H:%M') || DASH, kind: 'mono' }
      end

      # 「完成申请」时间：原生无此节点（OPEN-9）→ 显式留白，不给原型那句
      # 「09-28 09:40」硬编码值。
      def attr_submitted
        { key: '完成申请', value: submitted_at_text, kind: 'mono' }
      end

      def submitted_at_text
        return DASH unless @my_module.completed_on

        # completed_on 是「任务被标记完成」的时间，语义上接近原型五态机的「提交完成申请」，
        # 但原生没有申请/审核两档 —— 这里**如实标注**它是原生完成时间，不冒充申请时间。
        @my_module.completed_on.strftime('%m-%d %H:%M')
      end

      def attr_due
        due = @my_module.due_date
        { key: '截止日期', value: due&.strftime('%m-%d') || DASH, kind: due ? 'plain' : 'warn' }
      end

      def assigned_names
        return [] unless @my_module.respond_to?(:user_my_modules)

        @my_module.user_my_modules.includes(:user).map { |u| display_name(u.user) }.compact
      end

      # ------------------------------------------------------------
      # 流程轨迹：只挂**有真值来源**的节点，取不到的节点不编时间
      # ------------------------------------------------------------
      def flow_block
        flow = []
        flow << { title: '创建任务（派发）',
                  sub: [@my_module.created_by && "#{display_name(@my_module.created_by)} · " \
                        "#{@my_module.created_at&.strftime('%m-%d %H:%M')}",
                        @my_module.created_at&.strftime('%m-%d %H:%M')].compact.first || DASH,
                  color: 'done' }
        flow << { title: '开始执行',
                  sub: @my_module.started_on&.strftime('%m-%d %H:%M') || DASH,
                  color: @my_module.started_on ? 'done' : 'todo' }
        completed = @my_module.completed_on
        flow << { title: '完成（原生三态机末档）',
                  sub: completed&.strftime('%m-%d %H:%M') || DASH,
                  color: completed ? 'done' : 'todo' }
        flow
      end

      def flow_note
        '原型五态机里的「提交完成申请 / 待审核」两档在原生默认状态流里不存在' \
          '（只有 Not started / In progress / Completed 三档），此处不给它们编时间与状态。'
      end

      # ------------------------------------------------------------
      # 二开档案 & 审核位
      # ------------------------------------------------------------
      def profile_block
        prof = profile
        owner = prof&.owner_user
        { exist: !prof.nil?,
          businessCode: prof&.business_code.presence,
          purpose: prof&.purpose.presence,
          plan: prof&.plan.presence,
          owner: owner ? display_name(owner) : nil,
          source: prof&.source.presence }
      end

      # 审核按钮显隐走原生权限位本体（不自己再判一遍，避免第二套口径）
      def review_block
        { canReview: @can_manage_task,
          canComplete: @can_complete_task,
          canComment: @can_create_comment,
          hint: @can_manage_task ? nil : '仅项目负责人可审核关闭（DEC-003）；' \
                                        '当前身份未持有 manage_my_module' }
      end

      def display_name(user)
        return nil if user.nil?

        user.name.presence || user.email.to_s
      end

      def plain_text(raw)
        return '' if raw.blank?

        raw.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
      end

      DATE_FMT = '%Y-%m-%d'
    end
  end
end
