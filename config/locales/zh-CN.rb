# frozen_string_literal: true

# 中文序数词：number.nth.ordinals / ordinalized 需定义为 Proc，
# YAML 无法表达，故放于此 Ruby 文件（I18n.load_path 已包含 *.rb）。
# 签名必须与 ActiveSupport 内置 en 一致：i18n 引擎以 (key, options) 两个参数调用，
# 数字从 options[:number] 中读取。
{
  'zh-CN' => {
    number: {
      nth: {
        ordinals: lambda do |_key, _options|
          '第'
        end,
        ordinalized: lambda do |_key, options|
          "第#{options[:number]}"
        end
      }
    }
  }
}
