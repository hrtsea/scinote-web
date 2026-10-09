# frozen_string_literal: true

# ELN UI —— 资源中心 5 页签的真实数据装配
#
# 为什么不塞 controller：service 装配好后单测可直接调，不需要起 HTTP。
#
# 数据源（按页签）：
#   inventory    → 原生 Repository（Inventories）入口清单 —— 台账完全采用原生页承载，
#                  本页签只列「我能读哪些原生库存」，点击直达 /repositories/:id
#   ledger       → 原生 RepositoryLedgerRecord 全量流水（出入库记录，单列页签）
#   consume      → 消耗/执行明细表 eln_ui_consume_records（物资消耗 + 服务执行同一张表）
#   apply        → addon 自有 eln_ui_resource_applications
#   cost         → 同一张明细表（spec L108：花费归集唯一对外数据源）按 project/user 聚合；
#                  对账闸门 = 明细物资行 ↔ Ledger 任务消耗行一一对应（旧登记表已退役）
#
# 权限模型（access_control D8 同源同层）：列表层沿用原生 Canaid。
#   inventory/consume → can_read_repository? 对当前 team 下任一 active Repository 即可
#   apply/cost       → readable_by_user(project) 对当前 team 下任一 active Project 即可
# 写权限（新建申请、审批）不归本 Service 负责 —— controller/service 层另起。
#
# 字段名严格对齐原型（ELN系统-Vue3/src/views/ResCenter.vue + src/data/mock.js）：
#   inventory: repositories[]
#   ledger:    records[]
#   consume:   consumeRows[]
#   apply:     applyRows[]
#   cost:      costStats[] / byProject[] / byMember[]

module Scinote
  module ElnUi
    class ResCenterPayload
      DATE_FMT = '%Y-%m-%d %H:%M'
      # ⚠ 金额不带空格（'¥12,400'）：原型与项目详情页 cost_block 都是紧贴的，
      #   这里原来是 '¥ 12,400'，同一套 UI 里两种写法、测试断言也跟着写歪。
      #
      # 🔴 V1.25：实现搬到 Scinote::ElnUi::MoneyFormat（单一真源）——
      #   工作台「项目总花费」卡下钻到本页「花费」页签（SCN-DASH-9 对账不变式：
      #   **卡片 ≡ 下钻页**），两侧必须同一个 formatter，否则差一位小数就直接打脸。
      MONEY_FMT = ->(v) { Scinote::ElnUi::MoneyFormat.call(v) }

      class << self
        # 入口：current_user + current_team 由 controller 注入；
        # 不在这里 @current_user = current_user 是因为 service 既可能在 controller 里被调，
        # 也可能在 minitest 里被直接 new(...).call，不挑场景。
        def call(user:, team:, filters: {})
          new(user: user, team: team, filters: filters).call
        end
      end

      def initialize(user:, team:, filters: {})
        @user = user
        @team = team
        @filters = (filters || {}).with_indifferent_access
      end

      def call
        {
          inventory: inventory_block,
          ledger: ledger_block,
          consume: consume_block,
          apply: apply_block,
          cost: cost_block,
          # 共用元数据（顶部页头 / 调试用）
          meta: meta_block
        }
      end

      # 对外暴露「已按筛选条件过滤的明细行」，供导出端点复用（与 consume 页签同源同口径）。
      # 报告 §5 第 6 项 #12：明细表「按类型 / 项目 / 用户 / 时间范围筛选 + 导出」。
      def filtered_consume_records
        filter_consume_records(team_consume_records_all, @filters)
      end

      def self.filtered_consume_records(user:, team:, filters: {})
        new(user: user, team: team, filters: filters).filtered_consume_records
      end

      # ------------------------------------------------------------
      # 资源中心 4 张表的服务端网格契约（复用本 service 同一套取数/聚合，守单真源）
      #
      # 返回 JSON:API 形状 { data: [{id,type,attributes}], meta: {total_pages,total_count,filtered_count} }，
      # 与宿主 shared/datatable/table.vue 的 formatData 对齐（attributes 展开为行属性，
      # 所以 columnDefs.field 必须 == attributes 的键）。
      #
      # ⚠ 不在本方法里做第二套聚合：consume/ledger 走 filter_* + *_record_row（与展示/导出同源），
      #   byProject/byMember 直接取 cost_block 算好的数组（同一份 team_project_costs）。
      #   因此「页面底部 stats/recon」与「网格行」永远来自同一计算，不会漂。
      # ------------------------------------------------------------
      def grid_rows(dataset:, filters: {}, order: nil, page: 1, per_page: 20)
        page = [[page.to_i, 1].max, 1000].min
        per_page = [[per_page.to_i, 1].max, 100].min
        case dataset.to_s
        when 'consume'     then grid_consume(filters, order, page, per_page)
        when 'ledger'      then grid_ledger(filters, order, page, per_page)
        when 'by_project'  then grid_by_project(order, page, per_page)
        when 'by_member'   then grid_by_member(order, page, per_page)
        when 'apply'       then grid_apply(filters, order, page, per_page)
        else empty_grid
        end
      end

      private

      # ---- 服务端网格：消耗 / 执行明细（与 consume_block / 导出端点同源）----
      def grid_consume(filters, order, page, per_page)
        records = filter_consume_records(team_consume_records_all, (filters || {}).with_indifferent_access)
        rows = records.map { |cr| consume_record_row(cr) }
        rows = sort_rows(rows, order)
        paginate(rows, page, per_page)
      end

      # ---- 服务端网格：出入库记录（ledger_records 已按团队范围取齐，这里只筛/排/分页）----
      def grid_ledger(filters, order, page, per_page)
        f = (filters || {}).with_indifferent_access
        rows = ledger_records.select do |r|
          next false if f[:type].present? && r[:type] != f[:type]
          next false if f[:project].present? && r[:project] != f[:project]
          next false if f[:user].present? && r[:user] != f[:user]
          next false unless in_date_range?(r[:time], f[:range_from], f[:range_to])
          true
        end
        rows = sort_rows(rows, order)
        paginate(rows, page, per_page)
      end

      # ---- 服务端网格：按项目 / 按成员汇总（直接取 cost_block 算好的数组）----
      def grid_by_project(order, page, per_page)
        sort_rows(cost_block[:byProject], order).then { |rows| paginate(rows, page, per_page) }
      end

      def grid_by_member(order, page, per_page)
        sort_rows(cost_block[:byMember], order).then { |rows| paginate(rows, page, per_page) }
      end

      # ---- 服务端网格：资源申请单（可见范围沿用 apply_block 的 ResourceApprovalPolicy，
      #   服务端这道是安全边界，前端四维筛选只是展示层，两者不可混淆）----
      def grid_apply(filters, order, page, per_page)
        f = (filters || {}).with_indifferent_access
        rows = apply_rows.select do |r|
          next false if f[:status].present? && r[:statusRaw] != f[:status]
          next false if f[:kind].present? && r[:kind] != f[:kind]
          next false if f[:project_id].present? && r[:projectId].to_s != f[:project_id].to_s
          next false if f[:submitter_id].present? && r[:submitterId].to_s != f[:submitter_id].to_s
          true
        end
        rows = sort_rows(rows, order)
        paginate(rows, page, per_page)
      end

      # 与 apply_block 同源：同一道可见范围收口，避免「谁看得见」出现两条路径
      def apply_rows
        visible = Scinote::ElnUi::ResourceApprovalPolicy.visible_applications(user: @user, team: @team)
        visible.ordered.to_a.map { |a| apply_row(a) }
      end

      def empty_grid
        { data: [], meta: { total_pages: 1, total_count: 0, filtered_count: 0 } }
      end

      # 数值感知排序：某列「非空值全部可解析为数字」时按数字排（金额/数量/时间），否则整列按字典序。
      # 时间列是 'YYYY-MM-DD HH:MM'（零填充）⇒ 数字化后序 == 时间序，走数字分支即可。
      # 关掉客户端排序（宿主组件 comparator:()=>null），排序全部由这里收口。
      def sort_rows(rows, order)
        return rows if order.blank?

        o = order.is_a?(Array) ? order.first : order
        return rows if o.blank?

        col = (o.respond_to?(:dig) ? (o.dig(:column) || o.dig('column')) : nil).to_s
        return rows if col.blank?

        dir = (o.respond_to?(:dig) ? (o.dig(:dir) || o.dig('dir')) : nil).to_s == 'desc' ? :desc : :asc
        sym = col.to_sym

        # 整列判定（忽略空单元格，如入库行的「—」）：全可数字化 ⇒ 数字序，否则整列字典序。
        # ⚠ 必须整列判定，不能逐值判定 —— 否则「名称」这类列里带数字的行会被拆进数字桶，
        #   与其余行互相穿插，看起来像乱序。
        filled = rows.map { |r| row_value(r, sym, col) }.reject { |v| blank_cell?(v) }
        numeric = filled.any? && filled.all? { |v| money_to_d(v).is_a?(Numeric) }

        sorted =
          if numeric
            # 空单元格（无数量/无单价）排在末位
            rows.sort_by { |r| money_to_d(row_value(r, sym, col)) || Float::INFINITY }
          else
            rows.sort_by { |r| row_value(r, sym, col).to_s }
          end

        dir == :desc ? sorted.reverse : sorted
      end

      # ⚠ 行哈希是**符号键**（ledger_records / consume_record_row / apply_row / cost_block 全是
      #   `{ time:, qty:, ... }`），而 order 里的 column 是字符串 ⇒ 取值必须符号化。
      #   否则 r[col] 恒为 nil、整列静默不排序，只剩 dir 在反转默认顺序 ——
      #   症状极具误导性：「点表头方向反了，且点哪一列都一样」。
      def row_value(row, sym, str_key)
        return nil unless row.respond_to?(:[])

        if row.respond_to?(:key?)
          return row[sym] if row.key?(sym)
          return row[str_key] if row.key?(str_key)
        end
        row[sym]
      end

      def blank_cell?(v)
        s = v.to_s.strip
        s.empty? || ['—', '-', '–'].include?(s)
      end

      def money_to_d(v)
        return nil if v.nil?

        s = v.to_s.gsub(/[^\d.]/, '')
        return nil if s.blank?

        s.to_d
      rescue StandardError
        nil
      end

      def in_date_range?(time_str, from, to)
        return true if from.blank? && to.blank?

        d = parse_filter_date(time_str)
        return false if d.nil?
        return false if from.present? && d < parse_filter_date(from)
        return false if to.present? && d > parse_filter_date(to)

        true
      end

      def paginate(rows, page, per_page)
        total = rows.size
        offset = (page - 1) * per_page
        slice = rows.slice(offset, per_page) || []
        {
          data: slice.map.with_index do |r, i|
            { id: (r[:id].presence || "row-#{i}").to_s, type: (r[:type].presence || 'rc_row').to_s, attributes: r }
          end,
          meta: {
            total_pages: total.zero? ? 1 : (total.to_f / per_page).ceil,
            total_count: total,
            filtered_count: total
          }
        }
      end

      # ledger 筛选用候选（与展示同一份 ledger_records 抽，避免下拉漏项 / 双口径）
      def ledger_filter_options
        recs = ledger_records
        {
          projects: recs.reject { |r| ledger_placeholder?(r[:project]) }.map { |r| r[:project] }.uniq.sort,
          users: recs.reject { |r| ledger_placeholder?(r[:user]) }.map { |r| r[:user] }.uniq.sort
        }
      end

      def ledger_placeholder?(v)
        !v || v.to_s.starts_with?('—')
      end

      # ------------------------------------------------------------
      # 共用：当前 team 下「我能读」的库存模板 + 项目
      # ------------------------------------------------------------
      def readable_repositories
        @readable_repositories ||= Repository.active
                                             .where(team_id: @team.id)
                                             .with_granted_permissions(@user, RepositoryPermissions::READ)
                                             .distinct
                                             .to_a
      end

      def readable_projects
        @readable_projects ||= ::Project.where(team_id: @team.id, template: [false, nil])
                                         .distinct
                                         .active
                                         .readable_by_user(@user)
                                         .to_a
      end

      def repo_ids
        readable_repositories.map(&:id)
      end

      def project_ids
        readable_projects.map(&:id)
      end

      # 间接：team 下所有仓库 → 仓库下所有 row → EAV 反查所有 stock_value id
      # ⚠ 绕开 repository_ledger_records.repository_id（不存在）—— 走 sv 间接
      def team_stock_value_ids
        @team_stock_value_ids ||= begin
          row_ids = ::RepositoryRow.where(repository_id: repo_ids).pluck(:id)
          ::RepositoryStockValue.joins(:repository_cell)
                                .where(repository_cells: { repository_row_id: row_ids })
                                .pluck(:id)
        end
      end

      # ------------------------------------------------------------
      # ① 资源台账（原型 inventory.repositories）
      #
      # 台账完全采用原生 SciNote Inventories 承载：本 service 不再自绘
      # materials 表，只装配「当前用户可读的原生库存库」入口清单，
      # 前端点击直达 /repositories/:id（行管理 / Stock / 列自定义全在原生页）。
      # ------------------------------------------------------------
      def inventory_block
        {
          repositories: readable_repositories.map do |repo|
            {
              id: repo.id,
              name: repo.name.to_s,
              # ⚠ 原生 Repository 表没有 description 列（实测 columns: id/team_id/
              #   created_by_id/name/.../repository_template_id）。描述行改用
              #   「是否来自原生模板」生成，别引用不存在的列 —— 3 个用例一起炸的根因。
              description: repo.repository_template_id ? '来自原生库存模板' : '自建库存',
              rowsCount: ::RepositoryRow.where(repository_id: repo.id, archived: false).count
            }
          end
        }
      end

      # ------------------------------------------------------------
      # ② 出入库记录（单列页签，原型 ledger.records）
      #
      # 全量 RepositoryLedgerRecord 流水：入库 + 出库都列；
      # 消耗口径（只任务级出库）归 consume 页签，不在这里混。
      # ------------------------------------------------------------
      def ledger_block
        {
          records: ledger_records,
          # 出入库筛选用候选（与展示同一份 ledger_records 抽，避免下拉漏项 / 双口径）。
          # 占位串（'—（入库不写项目）' / '—'）不是真值，不能混入候选。
          filterOptions: ledger_filter_options
        }
      end

      # ①.2 ledgerRecords：所有 RepositoryLedgerRecord（按团队范围内 active repo）
      def ledger_records
        ::RepositoryLedgerRecord.where(repository_stock_value_id: team_stock_value_ids)
                                 .order(created_at: :desc)
                                 .limit(200)
                                 .map { |r| ledger_record_row(r) }
      end

      def ledger_record_row(r)
        sv = r.repository_stock_value
        # ⚠ StockValue → RepositoryRow 走 EAV（repository_cell.repository_row），不直接
        row = sv&.repository_cell&.repository_row
        # ⚠ 符号语义照抄原生（RepositoryStockLedgerZipExport L56）：
        #   任务行（MyModuleRepositoryRow ref）：amount 正 = 消耗（出库）、负 = 还回；
        #   库存行（Repository ref）：amount 负 = 出库、正 = 入库。
        type_text = if r.reference_type == 'MyModuleRepositoryRow'
                      r.amount.to_d.positive? ? '出库' : '入库'
                    else
                      r.amount.to_d.negative? ? '出库' : '入库'
                    end
        # 关联项目：my_module_references 里拿 project_id；空代表入库或非任务消耗
        proj_id = r.my_module_references.is_a?(Hash) ? r.my_module_references['project_id'] : nil
        proj = proj_id ? ::Project.find_by(id: proj_id) : nil
        qty = r.balance.to_d
        unit = r.unit.presence || stock_unit_of(sv)
        qty_text = r.amount.to_d.zero? ? '—' : "#{r.amount.abs} #{unit}".strip
        {
          time: date(r.created_at),
          type: type_text,
          name: row&.name.to_s.presence || '—',
          qty: qty_text,
          price: MONEY_FMT.call(r.unit_price),
          project: proj ? proj.name.to_s : '—（入库不写项目）',
          user: r.user ? (r.user.full_name.presence || r.user.email.to_s) : '—'
        }
      end

      # ------------------------------------------------------------
      # ② 消耗 / 执行明细（原型 consumeRows）
      #
      # ★ 真源（spec V1.21 L105）：**一张表同时收纳「已消耗物资」与「已执行服务」**
      #   两类行（eln_ui_consume_records = REQ-RES-CONSUME）：
      #     · 物资行 —— Ledger 任务消耗行由 decorator 同步登记（L106：与 Ledger 一一对应、
      #       同快照单价；登记动作挂在消耗链路内，本页签不提供人工录入）；
      #     · 服务行 —— 执行完成直接登记（L107，不写 Ledger；现阶段源 = 已完成的申请单
      #       中 kind=service 的项，执行单表落地后换源即可）。
      #   对外读的一侧是明细表（L108：花费归集唯一对外数据源）。
      #
      # ⚠ 全量加载（无 limit）：展示可截断，但「花费聚合」必须全量——
      #   花费页签与消耗页签共用本 loader，保证两个页签数字恒等（对账不变式）。
      # ------------------------------------------------------------
      # Ledger 侧（对账用，展示不用）：team 库存范围内任务消耗行
      def team_consume_rows_all
        @team_consume_rows_all ||= ::RepositoryLedgerRecord
                                   .where(repository_stock_value_id: team_stock_value_ids,
                                          reference_type: 'MyModuleRepositoryRow')
                                   .order(created_at: :desc)
                                   .to_a
      end

      # 明细表侧（对外真源）：团队项目范围内的消耗/执行明细行
      def team_consume_records_all
        @team_consume_records_all ||= ::Scinote::ElnUi::ConsumeRecord
                                      .where(project_id: team_project_ids)
                                      .order(occurred_at: :desc)
                                      .to_a
      end

      # 消耗 / 执行明细页签展示行（最新 200 条；聚合仍走全量 loader）
      #
      # ⚠ 合计走**花费口径**（物资剔设备模板 + 服务只计 settled，同 cost_block），
      #   不是「所有行金额裸加」—— 否则设备消耗会混进合计，与花费页签对不上。
      #   设备消耗行仍然展示在明细里（台账完整性），只是不计入合计。
      def consume_block
        all = filtered_consume_records
        rows = all.first(200).map { |cr| consume_record_row(cr) }
        # 🔴 V1.25：合计走 `ProjectCosts`（与花费页签同一个 aggregation 实例），
        #   不再在这里抄一份「剔设备 + 服务只计 settled」—— 抄两份必然漂。
        #   谓词复用同一个实例（设备模板仓库 id 在实例里 memo 过），不会重复查。
        charged = all.select { |cr| team_project_costs.chargeable?(cr) }
        {
          rows: rows,
          totalCount: all.size,
          serviceCount: rows.count { |r| r[:type] == '服务' },
          totalAmount: MONEY_FMT.call(charged.sum { |cr| cr.amount.to_d }.round(2)),
          # 筛选下拉选项（报告 §5 第 6 项 #12）：明细全量范围内出现过的项目 / 操作人，
          # 带 id 供前端导出时回传 project_id / user_id（与后端 filter_consume_records 同口径）。
          # 取全量而非前 200，否则下拉漏选项、导出与展示口径不一致。
          projects: consume_filter_projects,
          users: consume_filter_users
        }
      end

      # 明细全量范围内出现过的项目（去重、带 id）
      def consume_filter_projects
        pids = team_consume_records_all.filter_map(&:project_id).uniq
        return [] if pids.empty?

        projs = ::Project.where(id: pids).index_by(&:id)
        pids.map do |id|
          p = projs[id]
          { id: id, name: p ? p.name.to_s : "##{id}" }
        end
      end

      # 明细全量范围内出现过的操作人（去重、带 id）
      def consume_filter_users
        uids = team_consume_records_all.filter_map(&:user_id).uniq
        return [] if uids.empty?

        users = ::User.where(id: uids).index_by(&:id)
        uids.map do |id|
          u = users[id]
          { id: id, name: u ? (u.full_name.presence || u.email.to_s) : "##{id}" }
        end
      end

      def consume_record_row(cr)
        {
          time: date(cr.occurred_at),
          type: cr.kind == 'service' ? '服务' : '物资',
          name: cr.name.to_s.presence || '—',
          qty: "#{cr.quantity.abs} #{cr.unit.presence.to_s}".strip,
          price: MONEY_FMT.call(cr.unit_price),
          amount: MONEY_FMT.call(cr.amount),
          project: cr.project ? cr.project.name.to_s : '—',
          user: cr.user ? (cr.user.full_name.presence || cr.user.email.to_s) : '—',
          # 结算/验收状态（spec L109：服务行带结果状态；物资行无验收语义，恒 '—'）
          status: cr.material? ? '—' : (cr.settled? ? '已结算' : '待验收')
        }
      end

      # SCN-RES-CONSUME 末段：明细表「按类型 / 项目 / 用户 / 时间范围筛选」。
      # ⚠ 只作用于 consume 展示/导出侧；花费聚合（cost_block）始终走团队全量口径，
      #   不受筛选影响 —— 否则「按项目筛」会把跨项目花费也砍掉，对账块数字对不上。
      def filter_consume_records(records, filters)
        return records if filters.blank?

        result = records
        if (t = filters[:type].presence)
          result = if t.to_s == 'service'
                     result.select(&:service?)
                   else
                     result.select(&:material?)
                   end
        end
        if (pid = filters[:project_id].presence)
          result = result.select { |cr| cr.project_id.to_s == pid.to_s }
        end
        if (uid = filters[:user_id].presence)
          result = result.select { |cr| cr.user_id.to_s == uid.to_s }
        end
        from = parse_filter_date(filters[:range_from])
        to   = parse_filter_date(filters[:range_to])
        if from || to
          result = result.select do |cr|
            d = cr.occurred_at
            next false if d.nil?
            d = d.to_date
            (from.nil? || d >= from) && (to.nil? || d <= to)
          end
        end
        result
      end

      def parse_filter_date(value)
        v = value.presence
        return nil if v.nil?
        Date.parse(v.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # team 范围内所有项目 id（明细表侧的范围基准；与 Ledger 侧 team_stock_value_ids
      # 属同一「团队范围」但维度不同 —— 对账时两侧必须都收口到团队范围才可比）
      def team_project_ids
        @team_project_ids ||= ::Project.where(team_id: @team.id).pluck(:id)
      end

      # ------------------------------------------------------------
      # ③ 资源申请（原型 applyRows + 申请详情页）
      #
      # 范围：**按角色可见范围过滤**（SCN-RES-1 / SCN-RES-3，见 ResourceApprovalPolicy）
      #   · 项目负责人     → 其负责项目的全部申请（含草稿）
      #   · 被指名的审批人 → 其有资格审批的项目的全部申请（含草稿）
      #   · 其余团队成员   → 仅本人提交的全部申请（含草稿）
      # ⚠ 「谁看得见」只能在这里收口一次。前端再筛是**展示层**（Q4-2：四维筛选在客户端
      #   做），服务端这一道是**安全边界** —— 两者不是一回事，别指望前端替服务端把关。
      # ------------------------------------------------------------
      def apply_block
        visible = Scinote::ElnUi::ResourceApprovalPolicy.visible_applications(user: @user, team: @team)
        apps = visible.ordered.limit(200).to_a
        manageable = Scinote::ElnUi::ResourceApprovalPolicy.configurable_projects(@user, @team)
        {
          rows: apps.map { |a| apply_row(a) },
          totalCount: apps.size,
          # 新建申请表单（SCN-RES-APPLY-1）的项目下拉 —— 只列我 readable 的项目，
          # 与本 service 其余页签的 readable_projects 同源同口径
          projects: readable_projects.map { |p| { id: p.id, name: p.name.to_s } },
          # 新建申请表单（SCN-RES-TEST-1）的服务档案下拉 —— 服务类**必须**选一条：
          # 单价与「是否需验收」都从档案快照（spec L986 档案是服务目录的唯一载体）。
          # ⚠ 本表没有 team_id 列：档案是全局的，不走 team 过滤（测试基础档案
          #   本就由单位管理员跨团队维护，见 REQ-RES-ARCHIVE）。
          serviceCatalogs: service_catalog_blocks,
          # 材料类申请（ADR-0030 / SQ-2026-7783）必填「进入哪个库」——申请时选定，
          # 货到了才入库到该库（请购语义）。数据源与「库存台账」页签同源同口径
          # （readable_repositories），下拉里出现的都必须是用户本来就看得见的，
          # 否则等于用表单泄露别组的库房清单。
          repositories: apply_repositories,
          myModules: apply_my_modules,
          # 四维筛选的候选集合（Q4-2：筛选用它们在客户端做，服务端不下发过滤结果）。
          # ⚠ 候选只从**可见范围**里抽：把看不见的项目/人列进下拉，等于用 UI 泄露名单。
          filterOptions: apply_filter_options(apps),
          permissions: {
            scope: Scinote::ElnUi::ResourceApprovalPolicy.visible_scope(@user, @team),
            canConfigureApprovers: manageable.any?,
            manageableProjectIds: manageable.map(&:id)
          }
        }
      end

      # 材料类申请「进入哪个库」下拉：当前用户可读的**库**（Repository）列表。
      # 🔴 与上一轮删掉的「绑定库存条目」下拉只差一个词，语义完全相反：
      #   旧 = 绑 `RepositoryRow`（库里的**具体条目**）⇒ 料已在库里，去领 ⇒ 出库；
      #   新 = 绑 `Repository`（**库**）⇒ 料还没进库，货到了才进 ⇒ 入库。
      #   改这一块之前先读 docs/adr/0030-material-application-is-procurement.md。
      def apply_repositories
        readable_repositories.map { |repo| { id: repo.id, name: repo.name.to_s } }
      end

      # 材料类申请「关联任务」下拉：当前用户可读项目下的未归档任务。
      # 用途 = 记录这批料**预计消耗在哪个任务**（SCN-RES-APPLY-1 要求申请单可填
      # 「关联任务/实验记录本」），并作为详情页溯源时的**精确约束**：
      # 同一物料可能被多个任务消耗，只按条目反查会把别人的消耗也带出来。
      # ⚠ 出库动作本身**不在这里发生**——它由该任务的**原生消耗**触发
      #   （任务 stock_consumption → 写 RepositoryLedgerRecord），见 ADR-0030 D4。
      #
      # 🔴 my_modules 表**没有 project_id 列** —— 任务是挂在 Experiment 下的
      #   （MyModule belongs_to :experiment；Experiment belongs_to :project）。
      #   直接 where(project_id:) 会 PG::UndefinedColumn：生产端静默退化，
      #   测试端（transactional fixtures）把后续用例全炸成 InFailedSqlTransaction。
      #   一律走原生同款 joins(:experiment)（同 project_list_payload#build_stats_index）。
      def apply_my_modules
        pids = project_ids
        return [] if pids.empty?

        mods = ::MyModule.where(archived: false)
                         .joins(:experiment)
                         .where(experiments: { project_id: pids, archived: false })
                         .order(:id)
                         .limit(500)
                         .to_a
        return [] if mods.empty?

        exp_project = ::Experiment.where(id: mods.map(&:experiment_id).uniq).pluck(:id, :project_id).to_h
        projs = ::Project.where(id: exp_project.values.uniq).index_by(&:id)
        mods.filter_map do |mod|
          pid = exp_project[mod.experiment_id]
          proj = pid && projs[pid]
          next nil if proj.nil?
          {
            id: mod.id,
            name: mod.name.to_s,
            projectId: pid,
            projectName: proj.name.to_s
          }
        end
      end

      # 状态/类型枚举固定（spec 定死），项目与人从可见范围里抽
      def apply_filter_options(apps)
        {
          statuses: STATUS_LABELS.map { |value, label| { value: value, label: label } },
          types: [{ value: 'material', label: '材料' }, { value: 'service', label: '测试表征' }],
          projects: apply_option_projects(apps),
          submitters: apply_option_submitters(apps)
        }
      end

      def apply_option_projects(apps)
        pids = apps.filter_map(&:project_id).uniq
        return [] if pids.empty?

        projs = ::Project.where(id: pids).index_by(&:id)
        pids.map { |id| { id: id, name: projs[id] ? projs[id].name.to_s : "##{id}" } }
      end

      def apply_option_submitters(apps)
        uids = apps.filter_map(&:requestor_id).uniq
        return [] if uids.empty?

        users = ::User.where(id: uids).index_by(&:id)
        uids.map { |id| { id: id, name: users[id] ? display_name(users[id]) : "##{id}" } }
      end

      def display_name(user)
        user.full_name.presence || user.email.to_s
      end

      # SCN-RES-TEST-4：「列表必须呈现每个条目的『是否需验收』配置，使『为何尚未计入
      #   花费』可被解释」—— 所以 requiresAcceptance 一起下发，不只给 id 和名字。
      def service_catalog_blocks
        ::Scinote::ElnUi::ServiceCatalog.order(:name).map do |c|
          {
            id: c.id,
            name: c.name.to_s,
            unitPrice: c.unit_price.to_f,
            requiresAcceptance: c.acceptance_required?
          }
        end
      end

      # ⚠ projectId / submitterId / kind 是给前端「客户端四维筛选」用的**判定键**
      #   （Q4-2）：不能拿展示文案比字符串 —— 项目改名前后对不上、同名项目会串。
      def apply_row(a)
        first = a.item_list.first
        {
          id: a.id,
          no: a.no,
          type: first ? "#{item_kind_text(first)} · #{first['name']}" : '—',
          project: a.project ? a.project.name.to_s : '—',
          qty: total_qty_text(a),
          status: status_text(a.status),
          statusRaw: a.status,
          user: a.requestor ? display_name(a.requestor) : '—',
          time: a.submitted_at ? date(a.submitted_at) : date(a.created_at),
          projectId: a.project_id,
          submitterId: a.requestor_id,
          kind: first ? (first['kind'] || first[:kind] || 'material').to_s : 'material',
          # 🔴 「申请编号」列的下钻地址（原型 ELN系统-Vue3/src/views/ResCenter.vue L325
          #   `<router-link :to="`/eln_res_apply/${a.no}`">`）。
          #   目标由**后端**按宿主真实路由算好放进行里，前端只取用不拼串
          #   （铁律：路径词汇表只一套，见 entries/modifiers/router_link_host.js 头注）。
          #   取不到就 nil ⇒ 前端回落纯文本，不做「看着能点、点了 404」的假链接。
          detailUrl: apply_detail_url(a.no)
        }
      end

      # 宿主资源申请详情页 URL（/eln_res_apply/:no，routes.rb 的 eln_res_apply_detail）。
      # ⚠ addon 是 `isolate_namespace` 引擎：controller 的 `_routes` 指向**引擎自己的空
      #   route set**，裸调宿主路由助手必炸 UrlGenerationError（2026-10-09 实锤）。
      #   一律走全限定 `Rails.application.routes.url_helpers` —— 与
      #   project_list_payload#routes / notifications_payload#host_routes 同款既定通道。
      def apply_detail_url(no)
        return nil if no.blank?

        host_routes.eln_res_apply_detail_path(no)
      rescue StandardError => e
        Rails.logger.warn("[eln_ui] apply detail url failed: #{e.class}: #{e.message}")
        nil
      end

      def host_routes
        ::Rails.application.routes.url_helpers
      end

      def item_kind_text(item)
        (item['kind'] || item[:kind] || 'material') == 'service' ? '测试表征' : '材料'
      end

      def total_qty_text(a)
        items = a.item_list
        return '—' if items.empty?

        total = items.sum { |it| (it['qty'] || it[:qty] || 0).to_d }
        unit = items.first['unit'] || items.first[:unit] || ''
        "#{total} #{unit}".strip
      end

      STATUS_LABELS = {
        'draft'            => '草稿',
        'submitted'        => '待审批',
        'group_approved'   => '小组通过',
        'project_approved' => '已通过',
        'rejected'         => '驳回',
        'completed'        => '已完成'
      }.freeze

      def status_text(s)
        STATUS_LABELS[s] || s
      end

      # ------------------------------------------------------------
      # ④ 项目花费（原型 costStats / byProject / byMember）
      #
      # ★ 真源（2026-10-04 用户指令「花费必须与出入库/消耗明细对应上」+ 规格 V1.21
      #   L852/L854／L105~L108）：花费归集的**唯一对外数据源 = 消耗/执行明细表**
      #   （eln_ui_consume_records），按 project_id / user_id 两种口径分组聚合，
      #   金额取明细行自带的 amount 快照（= 数量 × 单价快照；decorator 与 Ledger 同一批写入，
      #   物资侧因此与流水同源同值）。
      #   花费 == 消耗/执行明细聚合 == 出入库记录中任务消耗行合计，构造性恒等。
      #
      #   - 入库不计花费（SCN-RES-COST-4）：明细表只收消耗/执行行，天然排除；
      #   - 快照单价（SCN-RES-COST-2）：读明细行 unit_price 快照，与物料改价无关；
      #   - 设备模板库存不计（SCN-RES-COST-6）：Ledger 侧 eligible 过滤已剔；
      #   - 服务执行（OPEN-9 已闭环）：明细表 kind=service 行真值，不写 Ledger
      #     （REQ-RES-TEST L107）；按 spec L109 只计 result_status=settled 的已结算行。
      #   - 旧 eln_ui_project_cost_items 登记表不再进本页签（REQ-RES-COST 全自动
      #     口径落地，规格明言「整体退役」；表与 seed 保留不删，仅退出花费口径）。
      # ------------------------------------------------------------
      # 单行花费贡献（★ 符号语义照抄原生 RepositoryStockLedgerZipExport L56）：
      # 任务消耗行（MyModuleRepositoryRow ref）amount 正 = 消耗（计花费）、
      # 负 = 还回（冲减花费）。统一式 amount × 快照单价，天然带符号。
      # （2026-10-04 修正：此前按「负=消耗」写反了，与原生相反 —— 生产实查
      #   原生消耗行 +200/+500/+20 实锤。）
      def cost_contribution(r)
        (r.amount.to_d * r.unit_price.to_d).round(2)
      end

      # SCN-RES-COST-6：设备模板库存不计入项目花费 —— 规格强制要求「排除判定须基于
      # 库存↔模板归属关系、不得依赖 Stock 缺失」。
      # 🔴 判定本体已抽到 Scinote::ElnUi::EquipmentTemplateFilter（写侧登记也要判，
      #   两边各写一份必然漂）；这里只做**本类内缓存**。
      # ⚠ RepositoryTemplate.equipment 返回的是**未落库的实例**（RepositoryTemplate.new(...)），
      #   不是 relation —— 要的是它的 name（i18n key），再按 name 回库里找真正 bootstrap 过的模板行。
      def equipment_template_probe
        return @equipment_template_probe if defined?(@equipment_template_probe)

        @equipment_template_probe = Scinote::ElnUi::EquipmentTemplateFilter.probe
      end

      def equipment_template_repo_ids
        @equipment_template_repo_ids ||= Scinote::ElnUi::EquipmentTemplateFilter
                                           .equipment_repository_ids
      end

      # ⚠ 这里判的是「**设备规则能不能查**」，**不是**「团队有没有设备模板」。
      #
      # 两种「空」曾被我混成一个（2026-10-06 修）：
      #   · **确实没有设备模板**（团队没 bootstrap 过 / 库存里没这类条目）
      #     → 没有哪条物资属于设备 → 全部物资都是普通消耗，正常计入花费；
      #       此时 `!include?` 恒真恰恰是**对**的，不是 fail-open。
      #   · **查不出设备模板**（RepositoryTemplate.equipment 拿不到）
      #     → 规则不可判 → fail-closed：一律不计，并让对账块把规则失效报出来。
      #
      # 前一版把两者都压成 `equipment_template_repo_ids.present? == false`，
      # 结果「团队没配设备模板」直接把**全部**物资判成不合格、花费恒 ¥0 ——
      # 比原来的 fail-open 还糟（开发生的是对的，只是设备消耗没被剔掉）。
      def equipment_rule_active?
        !equipment_template_probe.nil?
      end

      def cost_eligible?(r)
        return false unless equipment_rule_active?

        row = r.repository_stock_value&.repository_cell&.repository_row
        return false if row.nil?

        !equipment_template_repo_ids.include?(row.repository_id)
      end

      # 🔴 V1.25：`record_equipment_excluded?` 已从本类删除 —— 设备模板剔除搬去了
      #   `Scinote::ElnUi::ProjectCosts#equipment_row?`（单一真源）。这里再留一份副本，
      #   看到的就是「工作台一张数字、资源中心另一张数字」这种对不上账的温床。
      #   口径本体见 ProjectCosts 的同名方法（含三个 return false 的语义说明）。

      # 🔴 V1.25：计费判定（哪些行计入花费）已搬到 `ProjectCosts`（单一真源），
      #   本方法只剩「取数 + 排版」，**一行 filter 逻辑都不留在这儿** —— 工作台
      #   花的是同一个服务。不变式：本页「累计花费」≡ 工作台「项目总花费」卡
      #   （spec V1.25 · SCN-DASH-9）。
      def cost_block
        costs = team_project_costs
        material_num = costs.call.material
        service_num = costs.call.service
        total_num = costs.call.total
        material_rows = costs.chargeable_rows.select(&:material?)
        service_rows = costs.chargeable_rows.select(&:service?)

        cost_rows = material_rows + service_rows
        by_project = by_project_block(cost_rows)
        by_member = by_member_block(cost_rows)

        # 对账闸门（spec L106「明细表与 Ledger 一一对应、同快照单价」）：
        # 明细表物资行 ↔ Ledger 计费口径任务消耗行 —— 行数 + 金额双双核对。
        ledger_rows = ledger_consume_rows_eligible
        ledger_num = ledger_consume_material_total.round(2)

        {
          stats: [
            { label: '累计花费',    value: MONEY_FMT.call(total_num) },
            { label: '物资消耗',    value: MONEY_FMT.call(material_num) },
            { label: '服务执行',    value: MONEY_FMT.call(service_num) },
            { label: '涉及项目数',  value: "#{by_project.size} 个" }
          ],
          byProject: by_project,
          byMember: by_member,
          # 对账块：花费（明细表）↔ 出入库记录（Ledger）三方口径核对。
          # 判据不是「同源同公式所以必然相等」（那种恒等式谁改都不会假，等于没闸门），
          # 而是**明细行与流水行的一一对应**：行数差 1、金额差一分钱都立刻报不一致。
          # 历史行未登记明细（回填缺失）会在这里暴露，正是本闸门的价值。
          reconciliation: {
            # 设备模板剔除规则是否真的生效（false = 查不到 equipment 模板，两侧花费均不可信）
            equipmentRuleActive: equipment_rule_active?,
            detailMaterialRows: material_rows.size,
            ledgerMaterialRows: ledger_rows.size,
            detailMaterialTotal: MONEY_FMT.call(material_num),
            ledgerMaterialTotal: MONEY_FMT.call(ledger_num),
            consistent: material_rows.size == ledger_rows.size && (material_num - ledger_num).abs < 0.01
          }
        }
      end

      # 本 team 的花费聚合器（把明细行喂给 `ProjectCosts` 单一真源后的实例）。
      # ⚠ 必须 memo：设备模板剔除要沿明细行反查 Ledger → 库存行 → Repository，
      #   cost_block 与 consume_block 各自建一个实例 = 全量再反查一遍。
      def team_project_costs
        @team_project_costs ||= ::Scinote::ElnUi::ProjectCosts.for_rows(team_consume_records_all)
      end

      # Ledger 侧计费口径（剔除设备模板库存，SCN-RES-COST-6）：对账的「流水」那一头
      def ledger_consume_rows_eligible
        team_consume_rows_all.select { |r| cost_eligible?(r) }
      end

      def ledger_consume_material_total
        ledger_consume_rows_eligible.sum { |r| cost_contribution(r) }
      end

      def ledger_project_id(r)
        refs = r.my_module_references
        refs.is_a?(Hash) ? refs['project_id'] : nil
      end

      # 服务行判定：原生无 Service 仓库类型（REPOSITORY_APPENDABLE_TYPES 仅 Repository），
      # 本判定恒 false——保留分支是为将来若引入服务类库存行，花费能自动分桶。
      def service_ledger_row?(r)
        r.repository_row&.repository&.type.to_s.include?('Service')
      end

      # 按项目分组（明细表一侧；material/service 分桶，与 stats 同源同公式）
      #
      # ⚠ 排序按**数值**走，不按 MONEY_FMT 出来的钱串。旧写法
      #   `sort_by { |g| -g[:total].to_s.gsub(/[^\d.]/, '').to_d }` 会把负号一起
      #   当非数字抠掉：-900 和 -300 都被当成正数排序，最负的那条反而排到最后。
      #   项目名同理 —— 先批量取再 index_by，别每组各查一次。
      def by_project_block(rows)
        total = rows.sum { |cr| cr.amount.to_d }.round(2)
        groups = rows.group_by(&:project_id)
        projects = ::Project.where(id: groups.keys.compact.uniq).index_by(&:id)

        groups.map do |pid, crs|
          material = crs.select(&:material?).sum { |cr| cr.amount.to_d }.round(2)
          service = crs.select { |cr| cr.service? && cr.costable? }.sum { |cr| cr.amount.to_d }.round(2)
          proj = projects[pid]
          {
            id: pid,
            name: proj ? proj.name.to_s : (pid ? "##{pid}" : '—'),
            count: crs.size,
            material: MONEY_FMT.call(material),
            service: MONEY_FMT.call(service),
            total: MONEY_FMT.call((material + service).round(2)),
            ratio: total.zero? ? '0%' : "#{((material + service) / total * 100).round}%",
            sort_key: material + service
          }
        end.sort_by { |g| -g[:sort_key] }.map { |g| g.except(:sort_key) }
      end

      # 按操作人分组（spec L108 的「按 user_id 口径」）
      def by_member_block(rows)
        groups = rows.group_by(&:user_id)
        users = ::User.where(id: groups.keys.compact.uniq).index_by(&:id)

        groups.map do |uid, crs|
          user = users[uid]
          material = crs.select(&:material?).sum { |cr| cr.amount.to_d }.round(2)
          service = crs.select { |cr| cr.service? && cr.costable? }.sum { |cr| cr.amount.to_d }.round(2)
          {
            id: uid,
            name: user ? (user.full_name.presence || user.email.to_s) : '—',
            project: crs.filter_map { |cr| cr.project&.name }.uniq.join('、').presence || '—',
            count: crs.size,
            material: MONEY_FMT.call(material),
            service: MONEY_FMT.call(service),
            total: MONEY_FMT.call((material + service).round(2)),
            sort_key: material + service
          }
        end.sort_by { |g| -g[:sort_key] }.map { |g| g.except(:sort_key) }
      end

      # ------------------------------------------------------------
      # 元数据（页头副标题 / Tab 高亮 / 权限提示）
      # ------------------------------------------------------------
      def meta_block
        {
          team: @team.name.to_s,
          repositoryCount: readable_repositories.size,
          projectCount: readable_projects.size,
          canManage: @user.respond_to?(:permission_granted?) &&
                     @team.permission_granted?(@user, TeamPermissions::MANAGE)
        }
      end

      # ------------------------------------------------------------
      # 库存单位真源：RepositoryStockValue **没有 unit 列**（实测 15/15 条都走
      # repository_stock_unit_item → RepositoryStockUnitItem#data，生产里值是 "L"）。
      # 原生 ledger_records.unit 是出库当时拷下来的**快照**，优先用它；
      # 拿不到再回库存行反查。写 sv.unit 会直接 NoMethodError（不是 nil，是炸）。
      # ------------------------------------------------------------
      def stock_unit_of(sv)
        return '' if sv.nil?

        item = sv.repository_stock_unit_item
        item&.data.to_s
      rescue StandardError
        ''
      end

      def date(value)
        return nil if value.blank?

        value.respond_to?(:strftime) ? value.strftime(DATE_FMT) : value.to_s
      end
    end
  end
end
