# frozen_string_literal: true

# ELN UI —— 通用审批状态机骨架（REQ-RES-APPROVE 与 REQ-TASK-CLOSE 共用）
#
# 为什么抽这一层：资源申请单（二段式审批）和任务关闭（项目负责人审核）各有各的业务规则，
# 但**骨架完全一样** —— 白名单动作、按动作分派、gate 失败抛同一种错、结果回一个 ok 哈希。
# 这四件事复制两遍就会漂（有一次就出现过两处错误文案不一致），故只抽这一层；
# 动作本身（submit / approve_group / …）仍留在各自子类里，别把业务规则往基类塞。
#
# 统一错误类 WorkflowError 的意义在**调用方**：两个 controller 都写同一条 rescue，
#   `rescue WorkflowError → 422 { ok:false, error }`。错误类不统一，就得写两条 rescue，
#   漏一条 = 那个流程的 500 直接冒到用户脸上。
module Scinote
  module ElnUi
    class Workflow
      # 业务可预期的失败（controller 转 422，不炸 500）
      class WorkflowError < StandardError; end

      class << self
        # 子类声明自己的动作白名单（.call 里先过这道，挡住 send 任意方法名）
        def actions
          raise NotImplementedError, "#{name} 必须声明 actions"
        end

        # 找单 + 团队校验 + 分派，各流程的入参形状不同（no / my_module），故由子类实现
        def call(...)
          raise NotImplementedError, "#{name} 必须实现 call"
        end
      end

      def initialize(user:, team:)
        @user = user
        @team = team
      end

      # type 已在上面 case 过白名单，这里只负责落到方法上。
      # ⚠ 这里用 send 而不是 public_send：动作实现刻意放在 private 区（它们是状态机 internals，
      #   不是对外 API）。防「任意 send」靠的是上面那道 case 白名单，不是可见性。
      def run(type, reason)
        case type.to_s
        when *self.class.actions then send(:"apply_#{type}", reason)
        else raise(WorkflowError, "未知操作: #{type}")
        end
        result_payload
      end

      private

      attr_reader :user, :team

      # gate 失败一律抛同一种错 —— 「谁能做这一步」和「这一步做成了什么」是两件事，
      # 混在一起写就会长出「先改状态再校验权限」这种反向代码。
      def gate!(cond, msg)
        raise WorkflowError, msg unless cond
      end

      def result_payload
        raise NotImplementedError, "#{self.class} 必须实现 result_payload"
      end
    end
  end
end
