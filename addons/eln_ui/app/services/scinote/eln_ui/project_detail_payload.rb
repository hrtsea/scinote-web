# frozen_string_literal: true

# ELN UI —— 项目详情页的**真实**数据装配
#
# 为什么单独一个 Service（而不是塞进 controller）：
#   controller 只做「取 project + 判权限」，数据怎么从 SciNote 的领域模型翻译成
#   原型（ELN系统-Vue3/src/views/ProjectDetail.vue）要的字段，全部收在这里。
#   这样 addon 测试可以直接测 Service，不需要起 HTTP 会话，也不用碰权限链。
#
# 口径（重要，防止「改造」变成「编造」）：
#   SciNote 的 projects 表没有「项目编号」「项目来源」这类业务列，这里**不补造**——
#   编号用主键（#36），来源给 nil（页面显示「—」）。
#   原型里依赖画布演示值的面板（指标 / 花费 / 文档 / 归档）在真机没有对应数据源，
#   因此本 Service 不产出它们；页面在数组为空时显示「真实来源待接入」而不是填假数。
#
# 字段名一一对应原型的 mock（src/data/mock.js）：
#   projectBasic / members / experiments

module Scinote
  module ElnUi
    class ProjectDetailPayload
      # 原型「业务称谓」<-> SciNote UserRole 的映射。
      # 出处：原型 ProjectDetail 面板④ role-note —— "角色映射自 SciNote UserRole：
      # 项目负责人 = Owner、小组组长 = Normal user、组员 = Technician、观察者 = Viewer"。
      #
      # ⚠ 宿主（本 SciNote 版本）的**预定义** UserRole 实际是 Owner / User / Technician / Viewer，
      #   并没有 "Normal user" 这个名字（这是test 里实测到的，见 eln_ui 测试
      #   test_members_carry_real_user_and_role 的失败信息）。所以键必须对齐真名 'User'，
      #   同时保留原型原写法 'Normal user' 作为兼容键 —— 历史库/旧 seed 里可能还是那个名字。
      #   这是「原型业务称谓」→「宿主真实角色名」的映射表，加角色时记得一起加。
      ROLE_TITLES = {
        'Owner' => '项目负责人',
        'User' => '小组组长',
        'Normal user' => '小组组长',
        'Technician' => '组员',
        'Viewer' => '观察者'
      }.freeze

      # 原型头像配色（avatarPalette 的 5 个 key），按下标轮转，保证同一项目里稳定。
      AVATAR_COLORS = %w[blue green orange cyan purple].freeze

      DATE_FMT = '%Y-%m-%d'

      class << self
        def call(project)
          new(project).call
        end
      end

      def initialize(project)
        @project = project
      end

      def call
        {
          # 面包屑第一级「项目列表」的真实地址。前端写死 /projects 会跳去原生列表，
          # 而 addon 的用户预期是回到 /eln_project_list（工具栏 7 控件都在那页）。
          listUrl: '/eln_project_list',
          projectBasic: project_block,
          members: members_block,
          experiments: experiments_block,
          # ------------------------------------------------------------
          # 项目指标 / 项目文档（2026-10-04 落地）：原生无承载面 → addon 自有表
          #   eln_ui_project_metrics / eln_ui_project_documents
          # 项目花费：真源 = 原生 Ledger 任务消耗行（2026-10-04 切换，与资源中心
          # 花费页签同源同公式；旧 cost_items 登记表退役出花费口径）。表空 → 空数组
          # （不是不给键）：前端覆盖 mock 后走空态，绝不回落演示值。
          # ------------------------------------------------------------
          projectMetrics: metrics_block,
          requiredDocs: docs_block('required'),
          otherDocs: docs_block('other'),
          projectCost: cost_block,
          # 报告 §5 第 6 项 #11：任务审核关闭驱动指标状态（spec REQ-PM-INDICATOR / SCN-PM-IND-3/4/5）。
          # 真源 = 本项目所有任务的关闭审核单（eln_ui_task_close_requests）。前端据此把「指标达标」
          # 与「任务关闭完成率」挂钩并提供看板下钻入口（detailUrl 已下发）。
          taskCloseReview: task_close_review_block,
          # 报告 §5 第 6 项 #10：归档包预览 / 一键导出 / 置已结题禁建任务。
          # 原生 projects 已承载 archived 状态与归档动作（行菜单原生端点），本块只暴露
          # 真实归档态 + 导出入口，不重复造归档状态机。
          projectArchive: archive_block
        }
      end

      private

      # ------------------------------------------------------------
      # ① 项目基础信息（原型 pb：name/code/span/source/foundedAt/owner/team/status/metricProgress/description）
      # ------------------------------------------------------------
      def project_block
        {
          id: @project.id,
          name: @project.name.to_s,
          # projects 表无「项目编号」列 —— 用主键顶上，不编业务编号。
          code: "##{@project.id}",
          span: span_text,
          # 原生无「项目来源」字段（description 不承载来源）→ 显式 nil。
          # 页面会渲染成「项目来源」标签下留白 —— 这是原型（ProjectDetail.vue:114）的原生
          # 行为（{{ pb.source }} 没有兜底文案），**不许在这里编一个来源**；
          # 要显示「—」得改组件，而改组件就等于偏离原型，所以保持 nil 并在规格里记 OPEN。
          source: nil,
          foundedAt: date(@project.created_at),
          owner: owner_text,
          team: team_name,
          status: @project.archived? ? '已归档' : '执行中',
          # 原型这里写的是「指标 x/y 达标」；真机没有指标模型，改用**实验完成度**这一真实口径。
          metricProgress: metric_progress,
          # ⚠ 原型是按文本渲染 description 的（ProjectDetail.vue 第 125 行 {{ pb.description }}），
          #   但 SciNote 的 projects.description 存的是**后台富文本 HTML**（含 checkbox 之类），
          #   直接透传页面上会看到一整段 <div class="sci-checkbox-container">… 源码。
          #   这里按宿主自身的清洗器压成纯文本：**组件不改**（保持与原型同一份），
          #   让「原型 = 真机同一份组件」这条仍然成立，脏数据只在数据层收口。
          description: plain_description
        }
      end

      def plain_description
        raw = @project.description.to_s.strip
        return '' if raw.empty?

        # ⚠ 别写 Rails::Html::Sanitizer.full_sanitizer —— 这个版本（rails-html-sanitizer 1.7.1）
        #   返回的是 **类** 不是实例，直接 .sanitize 会 NoMethodError → 整页 500（实测）。
        #   ActionView::Base.full_sanitizer 才是稳定入口，只剥标签、保留文字。
        text = ActionView::Base.full_sanitizer.sanitize(raw).to_s
        text.gsub(/[[:space:]]+/, ' ').strip
      end

      def span_text
        from = @project.respond_to?(:started_at) ? (@project.started_at.presence || @project.created_at) : @project.created_at
        to = @project.due_date.presence ||
             (defined?(@project.done_at) && @project.done_at.presence) ||
             (defined?(@project.archived_on) && @project.archived_on.presence)
        to_text = date(to)
        to_text.presence ? "#{date(from)} ~ #{to_text}" : date(from).to_s
      end

      def owner_text
        user = supervised_user || creator_user
        return nil if user.blank?

        # ⚠ 兜底一律 fail-closed：查不到该成员在项目上的 user_assignment 行时，角色栏显示「—」。
        #   早先这里兜的是 'Owner'，等于把任何一个没有指派行的普通成员渲染成「张三（项目负责人）」
        #   —— 既违反「绝不回落演示文案」的项目铁律，回落方向还是权限最高的那一档。
        "#{user_full_name(user)}（#{role_name_for(user) || '—'}）"
      end

      def supervised_user
        return nil unless @project.respond_to?(:supervised_by_id)
        return nil if @project.supervised_by_id.blank?

        User.find_by(id: @project.supervised_by_id)
      end

      def creator_user
        @project.respond_to?(:created_by_id) ? User.find_by(id: @project.created_by_id) : nil
      end

      def user_full_name(user)
        (user.full_name.presence || user.email).to_s
      end

      def role_name_for(user)
        return nil if user.blank?

        row = @project.user_assignments.find_by(assignable_type: 'Project', user: user)
        row&.user_role&.name
      end

      def team_name
        return nil if @project.respond_to?(:team_id) && @project.team_id.blank?

        @project.respond_to?(:team) ? @project.team&.name : Team.find_by(id: @project.team_id)&.name
      end

      def metric_progress
        # 有真指标时用「指标 x/y 达标」（原型页头标签语义），否则退回实验完成度。
        if defined?(Scinote::ElnUi::ProjectMetric) &&
           Scinote::ElnUi::ProjectMetric.table_exists? &&
           (n = @project_metrics ||= Scinote::ElnUi::ProjectMetric.where(project_id: @project.id).count).positive?
        then
          ok = Scinote::ElnUi::ProjectMetric.where(project_id: @project.id, ok: true).count
          return "指标 #{ok}/#{n} 达标"
        end

        total = @project.experiments.count
        done = @project.experiments.count { |e| e.done_at.present? }
        "实验 已完成 #{done}/#{total}"
      end

      # ------------------------------------------------------------
      # ④ 项目指标（原型 mock.projectMetrics：name/target/current/ok）
      # ------------------------------------------------------------
      def metrics_block
        Scinote::ElnUi::ProjectMetric.where(project_id: @project.id).ordered.map do |m|
          { name: m.name.to_s, target: m.target.presence.to_s, current: m.current.presence.to_s, ok: m.ok }
        end
      end

      # ------------------------------------------------------------
      # ⑤ 项目文档（原型 mock.requiredDocs：name/ver/date/uploaded；
      #              mock.otherDocs：name/type/by/date）
      # ------------------------------------------------------------
      def docs_block(category)
        scope = Scinote::ElnUi::ProjectDocument.where(project_id: @project.id, category: category).ordered
        scope.map do |d|
          if category == 'required'
            {
              name: d.name.to_s,
              ver: d.version.presence || '—',
              date: d.uploaded_on.present? ? date(d.uploaded_on) : '—',
              uploaded: d.uploaded
            }
          else
            {
              name: d.name.to_s,
              type: d.doc_type.presence || '—',
              by: d.uploader.present? ? user_full_name(d.uploader) : '—',
              date: d.uploaded_on.present? ? date(d.uploaded_on) : '—'
            }
          end
        end
      end

      # ------------------------------------------------------------
      # ⑥ 项目花费（原型 mock.projectCost：total/splits/rows/note）
      #    ★ 真源（2026-10-04 用户指令「花费必须与出入库/消耗明细对应上」+
      #      spec V1.21 L105~L108）：本项目在**消耗/执行明细表**
      #      （eln_ui_consume_records = REQ-RES-CONSUME，project_id = 本项目）的行，
      #      与资源中心花费页签同源同口径（花费归集唯一对外数据源 = 明细表）。
      #      物资行由 Ledger 任务消耗行同步登记（L106 一一对应、同快照单价），
      #      服务行为执行完成登记（L107，不写 Ledger）。
      #      旧 eln_ui_project_cost_items 登记表退役出花费口径（表保留不删）。
      #      spec L109：服务行只有 settled（验收通过）才计入花费。
      # ------------------------------------------------------------
      def cost_block
        rows_ = project_consume_records
        return { total: nil, note: nil, scopes: cost_scopes, rows: [], splits: [] } if rows_.empty?

        material_rows = rows_.select(&:material?)
        service_rows = rows_.select { |cr| cr.service? && cr.costable? }
        total = material_rows.sum { |cr| cr.amount.to_d } + service_rows.sum { |cr| cr.amount.to_d }
        material = material_rows.sum { |cr| cr.amount.to_d }.round(2)
        service = service_rows.sum { |cr| cr.amount.to_d }.round(2)

        rows = [{
          category: '物资消耗',
          source: '消耗/执行明细表（Ledger 任务消耗行同步登记，spec L106）',
          basis: '数量 × 单价快照 unit_price（SCN-RES-COST-2）',
          amount: format_wan(material),
          share: share_text(material, total)
        }]
        splits = [{ label: '物资消耗（原生任务消耗）', amount: format_wan(material),
                    share: share_text(material, total), tone: 'primary' }]
        if service.positive?
          rows << { category: '服务执行', source: '服务执行明细（REQ-RES-CONSUME，settled）',
                    basis: '执行完成登记额（验收通过才计入，spec L109）', amount: format_wan(service),
                    share: share_text(service, total) }
          splits << { label: '服务执行（测试表征）', amount: format_wan(service),
                      share: share_text(service, total), tone: 'purple' }
        end
        {
          total: format_wan(total),
          note: '口径：SCN-RES-COST-1 明细表行 × 快照单价，按 project_id 归集；' \
                '入库不计花费（SCN-RES-COST-4），设备模板库存不参与（SCN-RES-COST-6）；' \
                '服务执行取明细表已结算行（spec L109）。',
          scopes: cost_scopes,
          rows: rows,
          splits: splits
        }
      end

      # 本项目的消耗/执行明细行（对外真源）
      def project_consume_records
        @project_consume_records ||= ::Scinote::ElnUi::ConsumeRecord
                                     .where(project_id: @project.id)
                                     .order(occurred_at: :desc)
                                     .to_a
      end

      # 本项目的 Ledger 任务消耗行（团队仓库范围 + project_id 命中）
      # ⚠ 设备模板仓库（SCN-RES-COST-6）整个从范围剔除：按模板归属显式排除
      def project_consume_rows
        @project_consume_rows ||= begin
          row_ids = ::RepositoryRow.where(repository_id: team_repo_ids).pluck(:id)
          sv_ids = ::RepositoryStockValue.joins(:repository_cell)
                                         .where(repository_cells: { repository_row_id: row_ids })
                                         .pluck(:id)
          ::RepositoryLedgerRecord
            .where(repository_stock_value_id: sv_ids, reference_type: 'MyModuleRepositoryRow')
            .where("my_module_references->>'project_id' = ?", @project.id.to_s)
            .order(created_at: :desc).to_a
        end
      end

      def team_repo_ids
        @team_repo_ids ||= begin
          equip_tmpl_ids = ::RepositoryTemplate.where(name: ::RepositoryTemplate.equipment.name).pluck(:id)
          equip_repo_ids = ::Repository.where(repository_template_id: equip_tmpl_ids).pluck(:id)
          ::Repository.active.where(team_id: @project.team_id).pluck(:id) - equip_repo_ids
        end
      end

      # 花费贡献（★ 原生符号语义，RepositoryStockLedgerZipExport L56）：
      # 任务行 amount 正 = 消耗（计花费）、负 = 还回（冲减）。统一式 amount × 快照单价。
      def cost_contribution(r)
        (r.amount.to_d * r.unit_price.to_d).round(2)
      end

      # 原生无 Service 仓库类型 → 恒 false；保留分支为将来服务类库存行自动分桶
      def service_ledger_row?(r)
        r.repository_row&.repository&.type.to_s.include?('Service')
      end

      def cost_scopes
        [{ key: 'project', label: '仅项目' }, { key: 'user', label: '仅用户' },
         { key: 'both', label: '项目 × 用户' }]
      end

      # 整数金额 → '¥55.3万'；去掉多余的 .0；不足 1 万 → '¥8,600'
      def format_wan(value)
        v = value.to_d
        return "¥#{v.round.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}" if v < 10_000

        wan = (v / 10_000).round(1)
        wan_text = wan.to_i == wan ? wan.to_i.to_s : wan.to_s
        "¥#{wan_text}万"
      end

      def share_text(amount, total)
        return '0%' if total.zero?

        "#{(amount / total * 100).round}%"
      end

      # ------------------------------------------------------------
      # ② 项目成员（原型 members：name/title/role/joined）
      # ------------------------------------------------------------
      def members_block
        rows = @project.user_assignments.where(assignable_type: 'Project').order(:created_at).to_a
        rows.each_with_index.map do |ua, i|
          user = User.find_by(id: ua.user_id)
          role = ua.user_role
          role_name = role&.name.to_s
          {
            name: user.present? ? user_full_name(user) : "##{ua.user_id}",
            title: ROLE_TITLES[role_name] || role_name.presence || '—',
            role: role_name.presence || '—',
            joined: date(ua.created_at),
            color: AVATAR_COLORS[i % AVATAR_COLORS.length]
          }
        end
      end

      # ------------------------------------------------------------
      # ③ 下属实验（原型 experiments：fullName/status/owner/progress/due）
      # ------------------------------------------------------------
      def experiments_block
        @project.experiments.order(:id).each_with_index.map do |exp, i|
          mods = exp.respond_to?(:my_modules) ? exp.my_modules.to_a : []
          total = mods.size
          done = mods.count { |m| m.completed_on.present? || m.archived.present? }
          {
            id: exp.id,
            name: exp.name.to_s,
            # 原型行内显示「EX1 · 硅胶配方与固化体系筛选」；真机实验主键是整数，用 "#{id} · 名称"。
            fullName: "#{exp.id} · #{exp.name}",
            # 下钻：走 addon 的实验详情页（前端不写死宿主路由）。
            # 原生 href "/projects/:pid/experiments/:id" 保留在 href 里做「去原生页」的旁路。
            href: "/projects/#{@project.id}/experiments/#{exp.id}",
            detailUrl: "/experiments/#{exp.id}/eln_exp_detail",
            status: experiment_status(exp, mods),
            owner: experiment_owner(exp, i),
            progress: { done: done, total: total },
            due: date(exp.due_date.presence || mods.map(&:due_date).compact.min)
          }
        end
      end

      def experiment_status(exp, mods)
        return 'done' if exp.done_at.present?
        return 'notstarted' if exp.created_at.present? && exp.started_at.blank? &&
                               mods.none? { |m| m.started_on.present? || m.completed_on.present? }

        'active'
      end

      def experiment_owner(exp, index)
        user = exp.respond_to?(:created_by_id) ? User.find_by(id: exp.created_by_id) : nil
        {
          name: user.present? ? user_full_name(user) : '—',
          initial: user.present? ? (user.initials.presence || user_full_name(user).first).to_s : '·',
          color: AVATAR_COLORS[index % AVATAR_COLORS.length]
        }
      end

      # ------------------------------------------------------------
      # ⑦ 任务关闭审核汇总（报告 §5 第 6 项 #11 · spec REQ-PM-INDICATOR / SCN-PM-IND-3/4/5）
      #
      # 真源 = 本项目所有任务的关闭审核单（eln_ui_task_close_requests）。指标达标不能只
      # 看用户手填的 ProjectMetric.ok —— 当存在关闭审核时，「指标状态由任务审核关闭驱动」：
      # 任务全部关闭才视为可复核达标（spec #11）。这里只下发事实，判定交给前端。
      # ------------------------------------------------------------
      def task_close_review_block
        mods = @project.experiments.flat_map { |e| e.respond_to?(:my_modules) ? e.my_modules.to_a : [] }
        mod_ids = mods.map(&:id)
        requests = Scinote::ElnUi::TaskCloseRequest.where(my_module_id: mod_ids).to_a
        closed   = requests.count(&:approved?)
        pending  = requests.count(&:pending?)
        rejected = requests.count(&:rejected?)
        total    = mods.size
        {
          total: total,
          closed: closed,
          pending: pending,
          rejected: rejected,
          # 全部任务关闭 → 指标达标可驱动（spec #11「由任务审核关闭驱动」）
          indicatorDriven: total.positive? && closed == total,
          tasks: mods.map do |m|
            latest = Scinote::ElnUi::TaskCloseRequest.latest_for(m)
            {
              id: m.id,
              name: m.name.to_s,
              state: latest&.status || 'none',
              stateLabel: latest ? latest.state_label : '未提交关闭申请',
              detailUrl: "/experiments/#{m.experiment_id}/my_modules/#{m.id}/eln_task_detail"
            }
          end
        }
      end

      # ------------------------------------------------------------
      # ⑧ 归档块（报告 §5 第 6 项 #10 · spec SCN-PM-ARCH-1/2/3）
      #
      # 原生 projects 已承载 archived 状态与归档动作（行菜单原生端点），本块只暴露真实
      # 归档态 + 导出入口，不重复造归档状态机。「置已结题禁建任务」由原生归档语义覆盖。
      # ------------------------------------------------------------
      def archive_block
        {
          archived: @project.archived?,
          archivedAt: @project.respond_to?(:archived_on) ? date(@project.archived_on) : nil,
          canExport: true,
          exportUrl: "/projects/#{@project.id}/eln_project_detail/export"
        }
      end

      def date(value)
        return nil if value.blank?

        value.respond_to?(:strftime) ? value.strftime(DATE_FMT) : value.to_s
      end
    end
  end
end
