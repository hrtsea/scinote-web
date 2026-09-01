# frozen_string_literal: true

Scinote::ProjectInsights::Engine.routes.draw do
  # P1 先留路由骨架；P3 实现 InsightsController#index 提供 JSON 数据
  get '/insights', to: 'insights#index', as: :insights
end
