# frozen_string_literal: true

# ELN UI —— 实验详情页（PAGE-EXP-DETAIL）的**真实**数据装配
#
# 与另两个 Payload 同一条规矩：**不编造**。原生没有的东西就显式留白/推导：
#   - 「实验设计变量」（DOE 的 DV 表）：原生没有这张表 → expDesignVars 给空数组，
#     面板渲染成空表。DOE 是纯二开（DEC-009），不是「原生有但没取出来」。
#   - 原型的 5 档任务状态（pending/active/submitted/pendingReview/closed）在原生
#     只有 3 档默认状态流（Not started / In progress / Completed）。这里**落到原型
#     取值域内**：Not started→pending、In progress→active、Completed→closed。
#     原生没有的 submitted / pendingReview 两档就让它不出现，不给它们编状态。
#
# 字段名一一对应原型的 mock（src/data/mock.js）：
#   expNav[{key,label}] expSubTabs[{key,label}] expDesignVars[{name,type,range,constraint}]
#   tasks[{id,name,status,owner:{name,initial,color},due}]
#
# ⚠ 组件侧消费边界（别搞错，与列表页不一样）：
#   ExperimentDetail.vue **不读 store/ui**，只认模板里 import 的 mock。
#   所以 experimentId 只能走 window 同步给 HostRouterLink 拼原生任务路由，
#   往 ui 塞 canCreateTask 是假生效（ProjectList.vue 的按钮才是 v-if="ui.canCreateProject"）。

module Scinote
  module ElnUi
    class ExpDetailPayload
      AVATAR_COLORS = %w[blue green orange cyan purple].freeze
      DATE_FMT = '%Y-%m-%d'

      # ⚠ 原生默认状态流三档 → 原型 status 取值域三档。
      #   映射理由：pending「待接收」≈ 未开始、active「进行中」= In progress、
      #   closed「已关闭」≈ Completed。颜色也沿用原型的 taskStatusLabel 文案。
      STATUS_MAP = {
        'Not started' => 'pending',
        'In progress' => 'active',
        'Completed' => 'closed'
      }.freeze

      # 设计变量表：原生无 DOE 变量 → 空。给「显式留白」而非隐身（面板照常渲染空表）。
      EMPTY_DESIGN_VARS = [].freeze

      # 空值占位 + 状态色，与 tokens.css 的 --status-* 三档一一对应（画布 3 档色板）。
      STATUS_COLOR = { 'notstarted' => 'var(--status-notstarted)',
                       'active' => 'var(--status-active)',
                       'done' => 'var(--status-done)' }.freeze

      class << self
        def call(experiment, user, can_create_task: false, can_manage_experiment: false)
          new(experiment, user, can_create_task: can_create_task,
                                can_manage_experiment: can_manage_experiment).call
        end
      end

      def initialize(experiment, user, can_create_task: false, can_manage_experiment: false)
        @experiment = experiment
        @user = user
        @can_create_task = can_create_task
        @can_manage_experiment = can_manage_experiment
      end

      def call
        {
          experimentId: @experiment.id.to_s,
          # 面包屑里原型的 <router-link to="/projects/PR1025240"> 是**写死的假项目 id**
          # （画布演示值），宿主不给真 id 就只能透传那条死链。给出来让 HostRouterLink 替换。
          projectId: project_id,
          # 下钻：面包屑第二级「项目名」要能点回**该项目**的addon 详情页。
          # 原来前端写死 to="/projects/PR1025240"（画布演示 id）→ 真机点进去 404。
          projectDetailUrl: project_id ? "/projects/#{project_id}/eln_project_detail" : nil,
          # 默认**左栏**页签：PRD §7.7「tasks 任务列表默认选中」（原生 my_modules#index
          # 也是任务列表）。原型初值 'overview' 会先显示「实验方案与方法」那块**原型
          # 硬编码的假文案**，首屏给假数据不行 → 真机默认落到真任务列表（SCN-EXP-DETAIL-4）。
          # ⚠ 是 expDefaultNav 不是 expDefaultSub：任务表格挂在 activeNav==='tasks'
          #   分支上，子页签 activeSub 只管「实验概况」内显示哪个 Pane（实测踩过）。
          expDefaultNav: 'tasks',
          # 进「实验概况」后默认显示哪个 Pane。
          # ⚠ 必须跟着 can_manage_experiment 走：原型 activeSub 默认 'design'，
          #   但 design 项在 DEC-001 下会被裁剪掉 → 结果是**面板显示 design 内容、
          #   子页签栏却点不到 design**（真机截图抓到：页签栏只有 3 项，底下却是
          #   「实验设计与配方优化」）。没权限就落到仍在页签栏里的 info。
          expDefaultSub: @can_manage_experiment ? 'design' : 'info',
          # 原型那三处演示文案（标题 / 面包屑项目名 / 状态徽标）在模板里是**写死的**，
          # 真机不注入就会顶着别人的项目名 —— 这里是它们的真值来源。
          experimentName: @experiment.name.to_s,
          projectName: project_name,
          statusText: STATUS_TEXT.fetch(status_of(@experiment), '进行中'),
          canCreateTask: @can_create_task,
          canManageExperiment: @can_manage_experiment,
          expNav: exp_nav,
          expSubTabs: exp_sub_tabs,
          expDesignVars: exp_design_vars,
          # 「实验目的」「实验方案与方法」两块 Pane 的正文：原生**没有**承载面
          # （experiments.description 是富文本、也不是「目的」），二开数据落在
          # eln_ui_experiment_profiles 里。都取不到就给空串 —— 页面上显式留白，
          # 绝不把原型那套演示文案（Dow ADH-6066 / 拉伸剪切强度 ≥ 8.0 MPa）当真值渲染。
          expPurpose: exp_purpose,
          expMethod: exp_method,
          # 「实验信息」Pane（画布 4:69 hidden 态）那 7 个字段的原型写死假值
          # （EX1 / 硅胶配方与固化体系筛选 / 张负责人 / 2026-09-30 / 1/3 任务）。
          # 这 7 格之前是整页最后一块假数据，真机不接就会顶着别人的项目名。
          expInfo: exp_info,
          tasks: tasks_block,
          status: status_of(@experiment)
        }
      end

      private

      # 三组中文文案，与原型 mock 的 statusLabel 逐字一致（进行中 / 未开始 / 已完成）。
      STATUS_TEXT = { 'active' => '进行中', 'notstarted' => '未开始', 'done' => '已完成' }.freeze

      def project_id
        return nil unless @experiment.respond_to?(:project_id)

        @experiment.project_id
      end

      def project_name
        return nil unless @experiment.respond_to?(:project) && @experiment.project

        @experiment.project.name.to_s
      end

      # 竖向导航：原型的两项固定，真值层面没有理由换，但保留注入位（宿主可裁剪）。
      def exp_nav
        [
          { key: 'overview', label: '实验概况' },
          { key: 'tasks', label: '实验任务' }
        ]
      end

      # ------------------------------------------------------------
      # 子页签（含权限裁剪）
      #
      # DEC-001：组员**不可见**「实验设计与配方优化」入口（直接访问则拒绝）。
      #   原生没有 DOE 模块，也没有对应的 Canaid 权限位，所以这里用实验维度的
      #   管理权限 ExperimentPermissions::MANAGE 近似「项目负责人/小组组长」口径。
      #   ⚠ 这是**近似映射**不是原生等价（记 OPEN-4）：原生 MANAGE 是「能改项目/实验
      #     设置」的权限位，DOE 模块的准入未来真做起来应该单独定权限位。
      # ------------------------------------------------------------
      def exp_sub_tabs
        base = [
          { key: 'info', label: '实验信息' },
          { key: 'purpose', label: '实验目的' },
          { key: 'method', label: '实验方案与方法' }
        ]
        return base unless @can_manage_experiment

        base + [{ key: 'design', label: '实验设计与配方优化' }]
      end

      # ------------------------------------------------------------
      # DOE 设计变量（纯二开表 eln_ui_design_variables）
      #
      # 原生完全没有 DOE，所以这张表**必须有数据才可能有行**。空表 → 空数组 →
      # 前端渲染空表（显式留白），与「原型写死 3 行假变量」是两回事。
      # ⚠ 表不存在（老实例没建过 eln_ui_*）时降级为空数组，而不是让整页 500。
      # ------------------------------------------------------------
      def exp_design_vars
        return EMPTY_DESIGN_VARS unless design_variable_class

        design_variable_class.where(experiment_id: @experiment.id).ordered.map do |v|
          {
            name: v.name.to_s,
            type: v.var_type.to_s,
            # 区间按 var_type 组装：categorical 没有 min/max，就不硬凑一个区间字符串
            range: range_text(v),
            constraint: v.constraint.to_s
          }
        end
      end

      def range_text(v)
        return DASH if v.range_min.blank? || v.range_max.blank?

        lo = format_number(v.range_min)
        hi = format_number(v.range_max)
        lo == hi ? "#{lo}#{v.unit.to_s}" : "#{lo} ~ #{hi}#{v.unit.to_s}"
      end

      # 12,4 的小数存进来是 Decimal → to_f 会把 5 变成 "5.0"（页面上就显示成
      # "5.0 ~ 25.0%" 这种假精度）。整数回落到不带小数，只有真小数才保留位数。
      def format_number(value)
        f = value.to_f
        return '0' if f.zero?

        f == f.floor ? f.to_i.to_s : f.to_s
      end

      # ⚠ 表存在性兜底：addon 自有表没建（老实例）时这些常量查不了，
      #   不能让「缺表」变成「整页 500」——降级为空，页面照样渲染。
      def design_variable_class
        klass = ::Scinote::ElnUi::DesignVariable if defined?(::Scinote::ElnUi::DesignVariable)
        klass&.table_exists? ? klass : nil
      rescue StandardError
        nil
      end

      def profile_class
        klass = ::Scinote::ElnUi::ExperimentProfile if defined?(::Scinote::ElnUi::ExperimentProfile)
        klass&.table_exists? ? klass : nil
      rescue StandardError
        nil
      end

      def profile
        return nil unless profile_class

        profile_class.where(experiment_id: @experiment.id).first
      end

      # 实验目的：二开档案优先；原生 description 兜底（原生**有**这一列，不算编造）。
      # 两者都空 → 空串（页面留白）。
      def exp_purpose
        (profile&.purpose.presence || native_description_text).to_s.strip
      end

      def native_description_text
        return '' unless @experiment.respond_to?(:description)

        raw = @experiment.description.to_s.strip
        return '' if raw.empty?

        # 与项目详情同源：原生存的是富文本 HTML，直接透传会看到一整段 <div class="sci-…"> 源码
        raw.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
      end

      # 实验方案与方法：只在二开档案里（原生无承载面）。空 → 空串。
      def exp_method
        (profile&.method.to_s).strip
      end

      # ------------------------------------------------------------
      # 「实验信息」Pane 七格 —— 每一格都要能说清它从哪来，说不清的就留白
      # ------------------------------------------------------------
      # 逐格来源（2026-10-04 接真时逐条核对）：
      #   实验编号  : 原生 Experiment#code = PrefixedIdModel 的 'EX' + 主键（真值，非编造）
      #   实验名称  : experiments.name
      #   状态      : 由 started_at / done_at 推导的三态（原生无 status 列）
      #   所属项目  : projects.name（与面包屑同源，不是另一份数据）
      #   实验负责人: 实验上的 UserAssignment（assignable_type='Experiment'）首选，
      #              退到 created_by —— 原生**没有**「实验负责人」这一列，
      #              所以不能凭空造，只能沿既有真数据推导（无则 '—'）
      #   计划完成  : experiments.due_date（原生列，可为 null → '—'）
      #   任务进度  : 状态为 Completed 的任务数 / 本实验任务总数（真推导）
      def exp_info
        {
          # 业务编号优先（二开档案里人工定的可读编号），取不到再落原生系统编码 EX+主键
          code: business_code || experiment_code,
          name: @experiment.name.to_s,
          state: STATUS_TEXT.fetch(status_of(@experiment), '进行中'),
          stateColor: STATUS_COLOR.fetch(status_of(@experiment), 'var(--status-active)'),
          project: project_name || DASH,
          owner: owner_name || DASH,
          due: due_date || DASH,
          progress: "#{completed_modules.size}/#{modules.size} 任务"
        }
      end

      DASH = '—'

      # 原生没有「实验编号」业务列，但 PrefixedIdModel 给了一个 code（EX + id）。
      # 与其在前端写死 'EX1'，不如直接用原生 code；code 拿不到（老记录）就留白。
      def experiment_code
        return @experiment.code.to_s if @experiment.respond_to?(:code)

        @experiment.id ? "EX#{@experiment.id}" : nil
      end

      # 业务编号（可空）：二开档案里人工定的可读编号（如 ELN-EXP-2026-001）。
      # 没填 → nil，由 call 里 `business_code || experiment_code` 回落到原生系统编码。
      def business_code
        profile&.business_code.presence
      end

      def due_date
        date(@experiment.respond_to?(:due_date) ? @experiment.due_date : nil)
      end

      # 实验负责人：① 二开档案里人工指定的 owner_user；② 实验上的 UserAssignment；
      # ③ 创建者。三级都拿不到就是 '—'（不编造）。
      # ① 之所以排在最前：原生「实验负责人」不是一列，推导（②③）得到的是**指派关系**，
      #    而档案里的 owner_user 才是业务上真正的「谁负责」。
      def owner_name
        user = profile&.owner_user.presence
        user ||= assigned_experiment_users.first
        user ||= experiment_creator
        user.blank? ? nil : display_name(user)
      end

      def experiment_creator
        return nil unless @experiment.respond_to?(:created_by)

        @experiment.created_by
      end

      def assigned_experiment_users
        return [] unless @experiment.respond_to?(:user_assignments)

        @experiment.user_assignments
                    .where(assignable_type: 'Experiment')
                    .includes(:user)
                    .order(:created_at)
                    .map { |ua| ua.respond_to?(:user) ? ua.user : nil }
                    .compact
      end

      def display_name(user)
        (user.respond_to?(:full_name) ? user.full_name.presence : nil) || user.email.to_s
      end

      def completed_modules
        modules.select { |m| m.my_module_status&.name.to_s == 'Completed' }
      end

      # ------------------------------------------------------------
      # 任务列表：当前实验下的**全部** MyModule（SCN-EXP-DETAIL-4：
      # 只含本实验的任务，不含同项目其它实验的任务 —— 天然满足，因为查询以 experiment 为单位）
      # ------------------------------------------------------------
      def tasks_block
        modules.map { |m| task_row(m) }
      end

      # ⚠ 记忆化：任务列表 / 已完成计数 / 进度分母都走这里，
      #   一次请求里 modules 会被问三遍，不缓存就是 3 条同样的查询。
      def modules
        return [] unless @experiment.respond_to?(:my_modules)

        @modules ||= @experiment.my_modules.readable_by_user(@user).order(:created_at).to_a
      end

      def task_row(my_module)
        {
          id: my_module.id.to_s,
          name: my_module.name.to_s,
          # 下钻终点：addon 任务详情页（两级原生路径 + /eln_task_detail，与 routes.rb 一致）。
          detailUrl: "/experiments/#{@experiment.id}/my_modules/#{my_module.id}/eln_task_detail",
          status: status_of_module(my_module),
          owner: owner_of(my_module),
          due: date(my_module.respond_to?(:due_date) ? my_module.due_date : nil)
        }
      end

      # 状态：取任务上的 MyModuleStatus 名，再过 STATUS_MAP 映射到原型取值域。
      # 映射不到（自定义状态流里出现新档位）→ 原样给出，宁可前端查不到文案，
      # 也不偷偷塞一个假状态（不编造原则）。
      def status_of_module(my_module)
        status = my_module.respond_to?(:my_module_status) ? my_module.my_module_status : nil
        return nil if status.blank?

        STATUS_MAP.fetch(status.name.to_s, status.name.to_s)
      end

      # 负责人：任务上的 UserAssignment（assignable_type MyModule），没有就是空头像。
      def owner_of(my_module)
        user = assigned_users(my_module).first
        return { name: '—', initial: '·', color: AVATAR_COLORS.first } if user.blank?

        avatar_of(user)
      end

      def assigned_users(my_module)
        return [] unless my_module.respond_to?(:user_assignments)

        my_module.user_assignments
                  .where(assignable_type: 'MyModule')
                  .includes(:user)
                  .order(:created_at)
                  .map(&:user)
                  .compact
      end

      def avatar_of(user)
        name = user.full_name.presence || user.email.to_s
        {
          name: name,
          initial: (user.respond_to?(:initials) ? user.initials.presence : nil).presence || name.to_s.first.to_s || '·',
          color: AVATAR_COLORS[(user.id || 0) % AVATAR_COLORS.length]
        }
      end

      # 实验三态（SCN-EXP-DETAIL-2）：由 started_at / done_at 推导，原生无 status 列。
      # 组件里那个「进行中」徽标是硬编码文案（原型缺口，记 OPEN-5），
      # 这里照样给出真值，将来按钮/徽标接上数据时直接用。
      def status_of(experiment)
        return 'done' if experiment.respond_to?(:done_at) && experiment.done_at.present?
        return 'notstarted' if experiment.respond_to?(:started_at) && experiment.started_at.blank?

        'active'
      end

      def date(value)
        return nil if value.blank?

        value.respond_to?(:strftime) ? value.strftime(DATE_FMT) : value.to_s
      end
    end
  end
end
