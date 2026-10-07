# frozen_string_literal: true

# 测试表征逾期豁免（eln_ui_service_strike_waivers · REQ-RES-TEST-STRIKE-3）
#
# 存在理由：spec V1.21 L1021/1035 要求「**必须支持管理员豁免**，以便对被禁人员临时
# 放行一次提交，并**记录豁免人与原因**；豁免不改变未回填事实本身，用后即失效」。
# 没有这张表，被冻结的人只能一直卡着（死锁），管理员也没有可追溯的放行凭证。
#
# 语义要点（照 spec 落，别在代码里再打折）：
#   · 豁免 = **放行一次提交**，不是消解占用 —— 补传前的占用继续累计；
#   · 用后即失效（used_at 落值）；
#   · granted_by / reason 是「谁放行的、为什么」的留痕。
class CreateElnUiServiceStrikeWaivers < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_service_strike_waivers do |t|
      t.references :user,        null: false, foreign_key: { to_table: :users }
      t.references :granted_by,  null: false, foreign_key: { to_table: :users }
      t.text   :reason
      t.datetime :used_at                     # nil = 未使用（可放行一次）
      t.timestamps
    end

    # 「这个人还有没有没用过的豁免」是唯一查询路径，走一次查 + 一次更新
    add_index :eln_ui_service_strike_waivers, %i[user_id used_at]
  end
end
