# frozen_string_literal: true

# 宿主接入片段（零侵入）：复制以下一行到 SciNote 宿主的 config/routes.rb
#
#   mount Scinote::AiEln::Engine => "/ai_eln"
#
# 引擎内部路由已在 enable=false 时整体短路（config/routes.rb 顶部 `return unless enabled?`）。
Rails.application.routes.draw do
  mount Scinote::AiEln::Engine => "/ai_eln"
end
