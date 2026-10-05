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
      MONEY_FMT = ->(v) {
        v = v.to_d
        int = v.round.to_i
        # 整数 / 两位小数都可，整数不补 .00
        formatted = int == v ? int.to_s : format('%.2f', v)
        "¥#{formatted.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      }

      class << self
        # 入口：current_user + current_team 由 controller 注入；
        # 不在这里 @current_user = current_user 是因为 service 既可能在 controller 里被调，
        # 也可能在 minitest 里被直接 new(...).call，不挑场景。
        def call(user:, team:)
          new(user: user, team: team).call
        end
      end

      def initialize(user:, team:)
        @user = user
        @team = team
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

      private

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
        { records: ledger_records }
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
        all = team_consume_records_all
        rows = all.first(200).map { |cr| consume_record_row(cr) }
        charged = all.reject { |cr| cr.material? && record_equipment_excluded?(cr) }
                     .select { |cr| cr.material? || (cr.service? && cr.costable?) }
        {
          rows: rows,
          totalCount: all.size,
          serviceCount: rows.count { |r| r[:type] == '服务' },
          totalAmount: MONEY_FMT.call(charged.sum { |cr| cr.amount.to_d }.round(2))
        }
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

      # team 范围内所有项目 id（明细表侧的范围基准；与 Ledger 侧 team_stock_value_ids
      # 属同一「团队范围」但维度不同 —— 对账时两侧必须都收口到团队范围才可比）
      def team_project_ids
        @team_project_ids ||= ::Project.where(team_id: @team.id).pluck(:id)
      end

      # ------------------------------------------------------------
      # ③ 资源申请（原型 applyRows + 申请详情页）
      #
      # 范围：当前团队下所有项目的申请单（不仅限 requestor = current_user）。
      # 后续可加 :for_user 过滤，但默认视图沿用原型「全员可见 + 提交人列」语义。
      # ------------------------------------------------------------
      def apply_block
        apps = Scinote::ElnUi::ResourceApplication.for_team(@team).ordered.limit(200).to_a
        {
          rows: apps.map { |a| apply_row(a) },
          totalCount: apps.size,
          # 新建申请表单（SCN-RES-APPLY-1）的项目下拉 —— 只列我 readable 的项目，
          # 与本 service 其余页签的 readable_projects 同源同口径
          projects: readable_projects.map { |p| { id: p.id, name: p.name.to_s } }
        }
      end

      def apply_row(a)
        {
          id: a.id,
          no: a.no,
          type: a.item_list.first ? "#{item_kind_text(a.item_list.first)} · #{a.item_list.first['name']}" : '—',
          project: a.project ? a.project.name.to_s : '—',
          qty: total_qty_text(a),
          status: status_text(a.status),
          statusRaw: a.status,
          user: a.requestor ? (a.requestor.full_name.presence || a.requestor.email.to_s) : '—',
          time: a.submitted_at ? date(a.submitted_at) : date(a.created_at)
        }
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
      # 库存↔模板归属关系、不得依赖 Stock 缺失」。equipment 模板 = 内置 i18n 键名模板。
      def equipment_template_repo_ids
        @equipment_template_repo_ids ||= ::Repository
                                          .where(repository_template_id: ::RepositoryTemplate
                                            .where(name: ::RepositoryTemplate.equipment.name))
                                          .pluck(:id)
      end

      def cost_eligible?(r)
        row = r.repository_stock_value&.repository_cell&.repository_row
        row.nil? || !equipment_template_repo_ids.include?(row.repository_id)
      end

      # SCN-RES-COST-6 在**明细表侧**的对应剔除：
      #   明细行是消耗链路里无条件登记的（decorator 不认识「设备模板不算花费」），
      #   所以花费归集必须自己再剔一遍 —— 否则设备消耗会混进花费。
      #   判定沿明细行的源流水反查库存行归属（与 Ledger 侧 cost_eligible? 同口径）。
      def record_equipment_excluded?(cr)
        return false unless cr.source_type == 'RepositoryLedgerRecord'

        ledger = ::RepositoryLedgerRecord.find_by(id: cr.source_id)
        return false if ledger.nil?

        row = ledger.repository_stock_value&.repository_cell&.repository_row
        row.present? && equipment_template_repo_ids.include?(row.repository_id)
      end

      def cost_block
        all = team_consume_records_all
        # 花费口径：物资 + 服务，且物资要先剔掉设备模板库存（SCN-RES-COST-6）；
        # 服务行按 spec L109 只计已结算
        material_rows = all.select { |cr| cr.material? && !record_equipment_excluded?(cr) }
        # 服务行：只计「已结算」—— spec L109「验收通过才计入项目花费」，
        # pending_acceptance 的明细行已在登记时写下状态，这里按状态过滤（不再靠 ¥0 占位）
        service_rows = all.select { |cr| cr.service? && cr.costable? }

        material_total = material_rows.sum { |cr| cr.amount.to_d }.round(2)
        service_total = service_rows.sum { |cr| cr.amount.to_d }.round(2)
        total = (material_total + service_total).round(2)

        cost_rows = material_rows + service_rows
        by_project = by_project_block(cost_rows)
        by_member = by_member_block(cost_rows)

        # 对账闸门（spec L106「明细表与 Ledger 一一对应、同快照单价」）：
        # 明细表物资行 ↔ Ledger 计费口径任务消耗行 —— 行数 + 金额双双核对。
        ledger_rows = ledger_consume_rows_eligible
        ledger_total = ledger_consume_material_total.round(2)

        {
          stats: [
            { label: '累计花费',    value: MONEY_FMT.call(total) },
            { label: '物资消耗',    value: MONEY_FMT.call(material_total) },
            { label: '服务执行',    value: MONEY_FMT.call(service_total) },
            { label: '涉及项目数',  value: "#{by_project.size} 个" }
          ],
          byProject: by_project,
          byMember: by_member,
          # 对账块：花费（明细表）↔ 出入库记录（Ledger）三方口径核对。
          # 判据不是「同源同公式所以必然相等」（那种恒等式谁改都不会假，等于没闸门），
          # 而是**明细行与流水行的一一对应**：行数差 1、金额差一分钱都立刻报不一致。
          # 历史行未登记明细（回填缺失）会在这里暴露，正是本闸门的价值。
          reconciliation: {
            detailMaterialRows: material_rows.size,
            ledgerMaterialRows: ledger_rows.size,
            detailMaterialTotal: MONEY_FMT.call(material_total),
            ledgerMaterialTotal: MONEY_FMT.call(ledger_total),
            consistent: material_rows.size == ledger_rows.size && (material_total - ledger_total).abs < 0.01
          }
        }
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
