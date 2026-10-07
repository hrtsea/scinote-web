# frozen_string_literal: true

module MyModuleStatusConsequences
  # 测试表征结果闸门（REQ-RES-TEST-STRIKE / SCN-RES-TEST-STRIKE-4）
  #
  # spec V1.21 L1040：「当 用户把含有测试表征执行单的任务标记为完成，则 系统经**自定义
  #   MyModuleStatusConsequence** 校验该任务是否存在「已到期仍未回填」的执行单；存在则
  #   默认**阻止完成**并给出欠交清单，缺失结果不得被静默通过」。
  #
  # ⚠ 本类故意**不**裹 `module Scinote::ElnUi` —— 这是本 addon「类体裹 Scinote::ElnUi」
  #   铁律的**唯一一处例外**：原生后果是 `my_module_status_consequences` 表上的 STI，
  #   `type` 列存的就是子类名；搬到 Scinote::ElnUi 命名空间下会变成另一个常量，
  #   表里那行认不出来 = 闸门根本挂不上。理由记在这里，别顺手"统一命名"。
  class ServiceResultGate < MyModuleStatusConsequence
    # 只有 forward（往完成方向走）才拦；往回退不拦 —— 否则撤销一次误操作
    # 都会被自己的闸门挡住（SCN-RES-TEST-STRIKE-4 只约束「标记为完成」这个时刻）。
    def forward(my_module)
      overdue = Scinote::ElnUi::ServiceStrikeBook.for_task(my_module)
      return if overdue.empty?

      missing = overdue.map { |row| Scinote::ElnUi::ServiceStrikeBook.overdue_line(row) }
      raise MyModuleStatus::MyModuleStatusTransitionError,
            { type: :service_result,
              limit: Scinote::ElnUi.service_result_strike_limit,
              missing: missing,
              # 原生 UI 弹的那一句话读的就是 error[:message]（MyModuleStatusConsequencesJob
              # 把整个 hash 塞进 my_modules.last_transition_error），少给一个键就等于
              # 拦下来了却什么都不显示 —— 拦得住、说不清，比不拦更难整改。
              message: "该任务有 #{missing.size} 项测试表征已过结果回填期限：" \
                       "#{missing.join('；')}" }
    end

    def backward(my_module); end
  end
end
