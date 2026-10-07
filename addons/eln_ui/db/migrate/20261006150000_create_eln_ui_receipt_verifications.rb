# frozen_string_literal: true

# 到货验收记录（eln_ui_receipt_verifications · REQ-RES-RECEIPT / ADR-0032）
#
# 存在理由：材料类请购**允许分多批到货**（SCN-RES-RECEIPT-3），于是「这张单验过几次、
# 每次谁验的、验了多少、结论是��、照片是哪几张」是**一对多**的事实 ——
# 挂到申请单的列上无处安放（`received_repository_row_id` 只能记最后一条落库条目，
# 且分批入库时其实**每批都落在同一条目**上，因为 find_or_create 按名称找/建）。
#
# ⚠ 为什么不挂照片到申请单：分批时「这批的照片」必须能单独指认（D6），
#   所以照片 `has_many_attached :photos` 挂在本表（宿主 ActiveStorage，不另建文件表）。
#
# 🔴 本表是**审计凭据**：判不通过时记录**保留**（不删），退回「待审批」后重走审批，
#   新一轮验收另起一行 —— 「验过几次」本身就是需要留痕的事实。
#   故不加 round 列：第几轮由 created_at 排序派生（可算的不存）。
class CreateElnUiReceiptVerifications < ActiveRecord::Migration[7.2]
  def change
    create_table :eln_ui_receipt_verifications do |t|
      t.references :resource_application, null: false,
                   foreign_key: { to_table: :eln_ui_resource_applications }
      # pending（申请人已交照片待验）/ passed（已验，入库已写）/ rejected（判不通过，已退回）
      # ⚠ 不用 Rails enum：宿主在 string 列上用 enum 会把值序列化成整数下标再 cast 回字符串
      #   （ConsumeRecord 的 kind 已实测踩过，kind_for_database => "0"，谓词恒 false）。
      t.string   :status, null: false, default: 'pending'
      t.references :verifier, foreign_key: { to_table: :users }   # 验货人（pending 时 nil）
      t.datetime :verified_at
      # 本批验货数量（SCN-RES-RECEIPT-3：验货人填「本批到货数量」，入库按它写）
      t.decimal  :qty, null: false, precision: 15, scale: 4, default: 0
      t.text     :note                                              # 验货备注
      t.text     :rejection_reason                                  # 拒收理由（rejected 时必填）
      t.references :created_by, foreign_key: { to_table: :users }   # 谁提交的这轮验收（申请人）

      t.timestamps
    end

    # 「这张单当前处于哪一档验收态」是唯一查询路径（详情页 + 收口判定 + 阻断计数三处共用）
    add_index :eln_ui_receipt_verifications, %i[resource_application_id status]
    # 分批历史按时间读；「累计已验数量」也走这条
    add_index :eln_ui_receipt_verifications, %i[resource_application_id created_at]
    # 管理员看「谁验的」用
    add_index :eln_ui_receipt_verifications, %i[verifier_id verified_at]
  end
end
