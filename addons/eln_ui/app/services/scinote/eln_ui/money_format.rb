# frozen_string_literal: true

module Scinote
  module ElnUi
    # 金额显示 —— **单一真源**
    #
    # 🔴 此前这份实现有两份一模一样的副本：`res_center_payload.rb` 的 `MONEY_FMT`
    #    lambda 与 `workbench_payload.rb` 的私有 `money`。两份各自漂移没人管，
    #   直到本轮（V1.25）工作台「项目总花费」卡要**下钻到资源中心花费页签**——
    #   同一条链路上出现两个 formatter，金额差一位小数就是肉眼可见的「对不上账」。
    #
    # 口径（三个展示位必须一致）：
    #   · 整数**不补小数**：¥300（不是 ¥300.00）
    #   · 真有零头才两位：¥300.50
    #   · 千分位逗号：¥12,400
    #   · ¥ 与数字**紧贴**（原型、项目详情页两侧都是紧贴的，历史上有过 '¥ 12,400'）
    #
    # ⚠ 别换成 `number_to_currency`：它恒输出两位小数，会把 ¥300 变成 ¥300.00，
    #   改完工作台上所有金额显示都变丑，且 `assert_equal '¥300'` 用例直接红。
    module MoneyFormat
      def self.call(value)
        v = value.to_d
        int = v.round.to_i
        formatted = int == v ? int.to_s : format('%.2f', v)
        "¥#{formatted.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end
    end
  end
end
