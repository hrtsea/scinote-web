# frozen_string_literal: true

# ELN UI —— 设备模板库存判定器（SCN-RES-COST-6 / SCN-RES-CONSUME-5）
#
# ## 为什么抽出来
#   规格要求「设备模板库存**不产生**明细行，且不计入任何花费」，这是**写侧**要求；
#   而 ResCenterPayload 早先只在**读侧**剔（consume_block / cost_block 各剔一遍）。
#   写侧要判、读侧也要判，两边各写一份必然漂 —— 故收到这里，model 与 payload 同一处。
#
# ## 两种「空」必须分开（这是本文件最容易写错的地方）
#   · **确实没有设备模板**（团队没bootstrap 过 / 库存里没这类条目）
#     → 没有哪条物资属于设备 → 全部物资都是普通消耗，正常计入/正常登记。
#       此时 `!include?` 恒真恰恰是**对**的，不是 fail-open。
#   · **查不出设备模板**（RepositoryTemplate.equipment 拿不到 / 表不存在）
#     → 规则不可判 → 写侧 **fail-closed 不登记**、读侧 **fail-closed 一律不计**，
#       并让对账块把「规则失效」报出来。
#
# 🔴 早先把两者压成 `equipment_template_repo_ids.present? == false`，
#   结果「团队没配设备模板」把**全部**物资判成设备、花费恒 ¥0 —— 比 fail-open 更糟。
#
# ## 判定依据（spec L920 强制）
#   「排除判定须基于**库存↔模板归属关系**、不得依赖 Stock 缺失」——
#   所以判据是 Repository.repository_template_id，绝不用「有没有库存值」来推断。
module Scinote
  module ElnUi
    class EquipmentTemplateFilter
      class << self
        # 🔴 这些memo 一律放在**实例**上，不放类变量：
        #   放类变量 = 跨用例/跨团队永不失效 —— 测试里每个用例造不同 team 的新库存，
        #   第一个算出的 id 列表会被后面所有用例复用（实测直接让设备模板用例假红）。
        #   写侧（每条 Ledger 行登记前）与读侧（payload 一次）都各建一个实例用，
        #   作用域小到「本次判定」，不会拿到过期数据。
        def probe
          ::RepositoryTemplate.respond_to?(:equipment) ? ::RepositoryTemplate.equipment : nil
        rescue StandardError
          nil
        end

        # 规则**能不能判**（不等于「团队有没有设备模板」）
        def rule_active?
          !probe.nil?
        end

        # 设备模板覆盖的库存 id 列表。规则不可判时返回 []，由调用方决定 fail 方向。
        # ⚠ 不 memo：跨调用可能新增库存（bootstrap / seed / 用户建库），缓存会漏。
        #   这条查询带 repository_template_id 索引，成本可接受；真成热点再上 request 级缓存。
        def equipment_repository_ids
          return [] unless rule_active?

          ::Repository.where(repository_template_id: ::RepositoryTemplate.where(name: probe.name))
                       .pluck(:id)
        rescue StandardError
          []
        end

        # ---- 写侧判定：这条物资到底该不该登记成明细行 ----

        # 规则不可判 → **返回 true 之外的处置由调用方决定**（本方法只回答「是不是设备」）。
        def equipment_row?(repository_id, equipment_repo_ids: nil)
          return false if repository_id.blank?
          return false unless rule_active?

          ids = equipment_repo_ids || equipment_repository_ids
          ids.include?(repository_id)
        end

        # 从一条 Ledger 行判断它是否属于设备模板库存。
        # 取不到归属（row / cell 缺失）→ **false**（不误杀正常物资），
        # 但真正的 fail-closed 在调用方：规则不可判时整条不登记。
        def equipment_ledger?(ledger)
          row = ledger.repository_row
          return false if row.nil?
          return false if row.repository_id.blank?

          equipment_row?(row.repository_id)
        end

        # 写侧唯一入口：这条 Ledger 行**是否禁止登记**明细行（SCN-RES-CONSUME-5）。
        #
        # ⚠ fail-closed 只在「规则不可判」时触发；「确实没有设备模板」不触发
        #   （否则团队没配设备就把全部物资拒了，花费恒 ¥0 —— 正是上面记的那个 bug）。
        def skip_material_row?(ledger)
          return true unless rule_active? # 规则不可判 → 不登记
          return false unless equipment_ledger?(ledger)

          true
        end

        # 供 payload 复用（保持 ResCenterPayload 原有私有方法名与语义不变）
        def cost_eligible?(r)
          return false unless rule_active?

          row = r.repository_stock_value&.repository_cell&.repository_row
          return false if row.nil?

          !equipment_row?(row.repository_id)
        end
      end
    end
  end
end
