# frozen_string_literal: true

module Scinote
  module WechatGateway
    # 用户级草稿索引：user_id -> { exp_id:, task_id:, body:, locked: }。
    # task_id 为「当前任务」：非空时后续文本/附件追加到该任务（MyModule）而非实验。
    # 忠实复刻 Python DraftStore；生产环境应换 Redis/DB（多 worker 一致性），
    # 见 docs/development/wechat-gateway-plan.md Ticket 01 注释。
    # locked 为草稿级软锁（/confirm 触发），仅阻止追加；真实 SciNote 只读
    # 强锁见 Ticket 05/08（需实例核实实验只读语义）。
    class SessionDraftStore
      def initialize
        @drafts = {}
      end

      def get(user_id)
        @drafts[user_id]
      end

      def put(user_id, exp_id, body = '', locked: false, task_id: nil)
        @drafts[user_id] = { exp_id: exp_id, task_id: task_id, body: body, locked: locked }
      end

      def pop(user_id)
        @drafts.delete(user_id)
      end

      # 把当前录入落点设到某任务（/settask）。要求已有当前实验，否则返回 false。
      def set_task(user_id, task_id)
        draft = @drafts[user_id]
        return false unless draft

        draft[:task_id] = task_id
        true
      end

      def clear_task(user_id)
        set_task(user_id, nil)
      end

      def locked?(user_id)
        @drafts[user_id]&.fetch(:locked, false) || false
      end

      # 锁定当前草稿（已无草稿返回 false）
      def mark_locked(user_id)
        draft = @drafts[user_id]
        return false unless draft

        draft[:locked] = true
        true
      end

      # 解除当前草稿锁定（已无草稿返回 false）
      def mark_unlocked(user_id)
        draft = @drafts[user_id]
        return false unless draft

        draft[:locked] = false
        true
      end
    end
  end
end
