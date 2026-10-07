# frozen_string_literal: true

# 测试表征「逾期未回填」计数、冻结与豁免（REQ-RES-TEST-STRIKE，SCN-RES-TEST-STRIKE-1~3）
#
# 口径（全部照 spec V1.21，不要在别处再打折）：
#   · **未回填** = 服务执行行 `result_file` 为空 —— 结果文件必须以 ResultAsset
#     显式绑到执行单（L998），只有"上传了文件但没绑"不算回填；
#   · **已到期** = 执行行 `occurred_at`（＝执行完成时刻）起超过
#     `service_result_grace_days`（默认 30 天，可配）；
#   · **未消解占用** = 已到期且未回填的执行单数；补传绑定后自动消解（L1025）；
#   · 占用达 `service_result_strike_limit`（默认 10，可配）→ 冻结该申请人
#     提交新的**测试表征**申请，并明示原因、阈值与欠交清单（L1030）；
#   · 管理员豁免 = 放行**一次**提交，用后即失效，且**不消解占用**（L1035）。
#
# ⚠ 本类只回答「算出来的账」，不做动作：要不要拦、拦了报什么错，由
#   ResourceApplicationWorkflow（申请入口）与 MyModuleStatusConsequences::ServiceResultGate
#   （任务完成闸门）各自决定。账只有一本，别让两处各算一遍。
module Scinote
  module ElnUi
    class ServiceStrikeBook
      class << self
        # ----------------------------------------------------------
        # 账：按申请人（谁申请谁欠账）
        # ----------------------------------------------------------
        def for_applicant(user_id)
          app_ids = ::Scinote::ElnUi::ResourceApplication.where(requestor_id: user_id).pluck(:id)
          overdue(service_rows(app_ids))
        end

        # ----------------------------------------------------------
        # 账：按任务（原生完成闸门用的就是这一路）
        # ----------------------------------------------------------
        def for_task(my_module)
          app_ids = ::Scinote::ElnUi::ResourceApplication.where(my_module_id: my_module.id).pluck(:id)
          overdue(service_rows(app_ids))
        end

        # 服务执行行（kind=service，源是申请单）
        def service_rows(app_ids, source_type: ConsumeRecord::SERVICE_SOURCE_TYPE)
          ::Scinote::ElnUi::ConsumeRecord
            .where(kind: 'service', source_type: source_type, source_id: app_ids)
        end

        # ----------------------------------------------------------
        # 判定
        # ----------------------------------------------------------
        def overdue(records, at: Time.current)
          grace = Scinote::ElnUi.service_result_grace_days
          records.to_a.select do |row|
            row.result_file.blank? && expired?(row, at: at, grace: grace)
          end
        end

        def expired?(row, at:, grace: nil)
          grace ||= Scinote::ElnUi.service_result_grace_days
          row.occurred_at.to_datetime + grace.days < at.to_datetime
        end

        # SCN-RES-TEST-STRIKE-2：未消解占用 ≥ 阈值 → 冻结
        def frozen?(user_id)
          for_applicant(user_id).size >= Scinote::ElnUi.service_result_strike_limit
        end

        # 冻结原因（含阈值与欠交清单，L1030「展示原因、阈值与欠交执行单清单」）
        # ⚠ 返回 nil 表示**没冻结** —— 用 nil 而不是空串，调用方才不会写出
        #   `if msg.present?` 这种把「没冻结」当成「冻结了但没理由」的岔路。
        def block_reason(user_id)
          limit = Scinote::ElnUi.service_result_strike_limit
          list = for_applicant(user_id)
          return nil unless list.size >= limit

          "未回填测试表征结果占用 #{list.size} 次，已达阈值 #{limit}，" \
            "暂缓提交新的测试表征申请。欠交清单：#{list.map { |r| row_label(r) }.join('、')}"
        end

        # ----------------------------------------------------------
        # 豁免（SCN-RES-TEST-STRIKE-3）
        # ----------------------------------------------------------
        # 管理员发放一次豁免（SCN-RES-TEST-STRIKE-3）：记录豁免人与原因，额度此时还没用掉。
        # ⚠ 只标记「欠账在这一次放行里被放过」，不消解占用 ——
        #   L1035「豁免不改变未回填事实本身」「豁免后该人员仍未回填，则其占用继续累计」。
        def grant_waiver!(user:, granted_by:, reason: nil)
          ::Scinote::ElnUi::ServiceStrikeWaiver.create!(
            user: user, granted_by: granted_by, reason: reason.to_s.strip.presence
          )
        end

        # 放行一次提交：找到未用过的豁免就把它用掉（used_at 落值），并返回 true。
        def consume_waiver!(user_id)
          waiver = ::Scinote::ElnUi::ServiceStrikeWaiver.unused
                                                       .where(user_id: user_id)
                                                       .order(:created_at)
                                                       .first
          return false if waiver.nil?

          waiver.consume!
          true
        end

        # 欠交清单里给管理员看的那一行（闸门拦下时给的就是这个）。
        # 两个名字都还有调用方，别只留一个：闸门（service_result_gate.rb）对外说 overdue_line，
        # block_reason 内部把多条并进一句话时用 row_label。
        def overdue_line(row)
          row_label(row)
        end

        def row_label(row)
          task = ::Scinote::ElnUi::ResourceApplication.find_by(id: row.source_id)&.my_module
          due = row.occurred_at.to_datetime + Scinote::ElnUi.service_result_grace_days.days
          "［#{(task&.name).presence || '未关联任务'}］#{row.name} · #{row.occurred_at.to_date}" \
            "（须于 #{due.to_date} 前回填）"
        end
      end
    end
  end
end
