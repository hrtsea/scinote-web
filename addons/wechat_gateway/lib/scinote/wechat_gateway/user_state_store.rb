# frozen_string_literal: true

module Scinote
  module WechatGateway
    # 待选项目的默认有效期（秒）。超时后 pending 视为不存在，按「无预设」重新引导。
    DEFAULT_PENDING_TTL = 15 * 60

    # 用户级长期状态的访问层：默认项目（DB 持久化）+ 待选项目 pending。
    # 与 SessionDraftStore（进程内、只管当前草稿）分离：
    #   长期状态  -> 本文件（DB，跨消息/跨进程/跨通道）
    #   当前草稿  -> SessionDraftStore（内存 Hash，仅本进程内，见已知限制）
    class UserStateStore
      def initialize(ttl: DEFAULT_PENDING_TTL)
        @ttl = ttl
      end

      # ---- 默认项目 ----
      def default_project_id(user_id)
        row(user_id)&.default_project_id
      end

      def set_default_project(user_id, project_id)
        UserState.for(user_id).update!(default_project_id: project_id)
        project_id
      end

      def clear_default_project(user_id)
        r = row(user_id)
        r&.update!(default_project_id: nil)
        nil
      end

      # ---- 待选项目 pending ----
      # 返回 nil（无 pending / 已过期），或 { action:, payload:, expires_at: }。
      # payload 为 Hash（键为字符串，jsonb 往返后一致）。
      def pending(user_id)
        r = row(user_id)
        return nil if r.nil? || r.pending_action.blank?
        return nil if r.pending_expires_at && r.pending_expires_at < Time.now

        { action: r.pending_action, payload: normalize_payload(r.pending_payload),
          expires_at: r.pending_expires_at }
      end

      def set_pending(user_id, action, payload, ttl: @ttl)
        UserState.for(user_id).update!(
          pending_action: action,
          pending_payload: payload || {},
          pending_expires_at: Time.now + ttl.to_i
        )
      end

      def clear_pending(user_id)
        r = row(user_id)
        return nil unless r

        r.update!(pending_action: nil, pending_payload: {}, pending_expires_at: nil)
      end

      private

      def row(user_id)
        UserState.find_by(scinote_user_id: user_id.to_i)
      end

      def normalize_payload(p)
        case p
        when Hash then p
        else {}
        end
      end
    end

    # 进程内实现：接口与 UserStateStore 完全一致，供单测 / 无 DB 场景注入。
    # 不持久化（进程重启即丢），生产请注入 UserStateStore。
    class MemoryUserStateStore
      def initialize(ttl: DEFAULT_PENDING_TTL)
        @ttl = ttl
        @rows = {}
      end

      def default_project_id(user_id)
        r(user_id)[:default_project_id]
      end

      def set_default_project(user_id, project_id)
        r(user_id)[:default_project_id] = project_id
        project_id
      end

      def clear_default_project(user_id)
        r(user_id)[:default_project_id] = nil
        nil
      end

      def pending(user_id)
        row = r(user_id)
        return nil if row[:pending_action].nil?
        return nil if row[:pending_expires_at] && row[:pending_expires_at] < Time.now

        { action: row[:pending_action], payload: stringify(row[:pending_payload] || {}),
          expires_at: row[:pending_expires_at] }
      end

      def set_pending(user_id, action, payload, ttl: @ttl)
        r(user_id).merge!(
          pending_action: action,
          pending_payload: payload || {},
          pending_expires_at: Time.now + ttl.to_i
        )
      end

      def clear_pending(user_id)
        r(user_id).merge!(pending_action: nil, pending_payload: {}, pending_expires_at: nil)
      end

      # 测试辅助：直接把 pending 推到过期，验证超时分支
      def expire_pending!(user_id)
        r(user_id)[:pending_expires_at] = Time.now - 1
      end

      private

      def r(user_id)
        @rows[user_id.to_i] ||= { default_project_id: nil, pending_action: nil,
                                  pending_payload: {}, pending_expires_at: nil }
      end

      def stringify(h)
        h.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      end
    end
  end
end
