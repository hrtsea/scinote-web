# frozen_string_literal: true

# 未验货积压的「账」（REQ-RES-RECEIPT-4 · ADR-0032）
#
# ⚠ 本类与 `ServiceStrikeBook` **同构**，这是刻意的（用户指令：「跟测试服务未及时上传结果
#   采用相同的处理」）。同构的部分：
#     · 三个方法同名同义：`frozen?` / `block_reason` / `consume_waiver!`；
#     · 计数口径同为**按申请人跨项目**（不按项目 —— 按项目的话换个项目就能绕过，
#       跟 ServiceStrikeBook 的 `for_applicant` 一致）；
#     · 豁免**直接复用同一张 `ServiceStrikeWaiver` 表与同一个消费方法**，
#       不另建豁免表、不另写消费逻辑；
#     · `block_reason` **未冻结时返回 nil**（不是空串）—— 调用方写
#       `if msg.present?` 才会把「没冻结」误当成「冻结了但没理由」。
#
# 与 `ServiceStrikeBook` **唯一的差别**（也是必须差别的地方）：数的不是同一件事 ——
#   ServiceStrikeBook 数「逾期未回填的服务执行单」；
#   本类数「已终审通过、但累计验货量仍未达申请量的**材料**申请」。
#
# 🔴 两者是**镜像**而非合并：`SCN-RES-TEST-STRIKE-2` 只冻测试表征（材料照常入），
#   `SCN-RES-RECEIPT-4` 只冻材料（服务照常入）。合起来覆盖申请类型全集，
#   而**机制只有一份**（阈值同一处模块级配置、豁免同一张表、闸门同一处代码）。
module Scinote
  module ElnUi
    class ReceiptPendingBook
      class << self
        # 账：按申请人（谁申请谁欠账）——与 ServiceStrikeBook#for_applicant 同口径
        #
        # 🔴🔴 **只数材料类**，这不是可选的过滤，是规则本身：
        #   服务类申请**永远不经历货**（不建库存，SCN-RES-APPROVE-4），把它算成「未验货」
        #   会让「已完成终审、只等服务执行」的单**凭空占一个未验货名额**，
        #   数量攒够就把新建材料申请误冻 —— 实测踩过：seed 的 `SQ-2026-0092`
        #   （服务、project_approved）被算进来，unverified_count 凭空 +1。
        #   修法是判 `material?` 而不是判「有没有验收记录」：后者服务类恒为 0，
        #   看起来像「已达标」又不像，绕一圈还是错。
        def for_applicant(user_id)
          apps = ::Scinote::ElnUi::ResourceApplication
                  .where(requestor_id: user_id, status: 'project_approved')
          apps.to_a.select { |a| a.material? && !completed_threshold_reached?(a) }
        end

        # 判定（SCN-RES-RECEIPT-4：未验货申请数 ≥ 阈值 → 冻结新建材料申请）
        def frozen?(user_id)
          for_applicant(user_id).size >= Scinote::ElnUi.receipt_pending_block_limit
        end

        # 冻结原因（阈值 + 未验货单号清单，可跳转去处理）。
        # ⚠ 返回 nil 表示**没冻结** —— 理由同 ServiceStrikeBook#block_reason。
        def block_reason(user_id)
          limit = Scinote::ElnUi.receipt_pending_block_limit
          list = for_applicant(user_id)
          return nil unless list.size >= limit

          "你有 #{list.size} 张材料申请已终审通过但尚未验货入库，已达阈值 #{limit}，" \
            "暂缓新建材料申请。未验货清单：#{list.map { |a| row_label(a) }.join('、')}"
        end

        # 豁免：放行一次，**直接委托**给 ServiceStrikeBook ——
        # ⚠ 委托而不是复刻，是「机制只有一份」最硬的一处：
        #   同一张 ServiceStrikeWaiver 表、同一个 consume_waiver!，
        #   所以「服务逾期」与「材料未验货」两重冻结命中时，**一次豁免只放行其中一处**
        #   （这是复用带来的真实约束，spec SCN-RES-RECEIPT-4 末条已写明）。
        def consume_waiver!(user_id)
          Scinote::ElnUi::ServiceStrikeBook.consume_waiver!(user_id)
        end

        private

        def completed_threshold_reached?(app)
          ::Scinote::ElnUi::ReceiptVerification.completed_threshold_reached?(app)
        end

        # 清单里给管理员看的那一行（闸门拦下时给的就是这个）
        def row_label(app)
          "#{app.no}（申请 #{::Scinote::ElnUi::ReceiptVerification.applied_qty(app)}，" \
            "已验 #{::Scinote::ElnUi::ReceiptVerification.verified_qty(app)}）"
        end
      end
    end
  end
end
