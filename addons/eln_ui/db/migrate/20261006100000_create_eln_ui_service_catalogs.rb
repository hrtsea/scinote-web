# frozen_string_literal: true

# 测试表征服务档案（eln_ui_service_catalogs · REQ-RES-ARCHIVE / REQ-RES-TEST）
#
# 存在理由：spec V1.21 L986「服务不建库存、不设额度，服务目录只在**资源基础档案**
# 维护，其单价作为登记时的快照来源」。也就是说服务行的 `unit_price` 只有一个合法
# 取值来源 —— 档案条目，不能由申请表单自由填（填了就没有任何 provenance，
# 花费行无法向管理员解释「这 ¥1200 是怎么来的」）。档案条目同时承载
# `requires_acceptance`（spec L1010：默认开启＝需验收，验收通过才计入花费）。
#
# ⚠ 与 `SCN-RES-COST-6` 的关系：设备模板库存不属本规则覆盖范围（不计花费），
#   本表不收设备条目。
class CreateElnUiServiceCatalogs < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_service_catalogs do |t|
      t.string  :name, null: false                     # 测试项目
      t.decimal :unit_price, null: false, precision: 12, scale: 2, default: 0
      t.integer :cycle_days                            # 周期（天）
      t.string  :vendor                                # 服务商
      # spec L1010「requires_acceptance … 默认开启＝需验收」——
      # ✅ 这里就是默认值 true 的落点，别在代码里再兜一层「默认 true」。
      t.boolean :requires_acceptance, null: false, default: true

      t.timestamps
    end

    # 档案页 / 申请表单下拉都按名称检索（唯一不是硬要求：同一测试项目可有不同
    # 服务商报价，故只加普通索引，不建 unique）
    add_index :eln_ui_service_catalogs, :name
  end
end
