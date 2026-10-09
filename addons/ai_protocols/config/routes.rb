# frozen_string_literal: true

Scinote::AiProtocols::Engine.routes.draw do
  # --- 旧：服务端三步页（保留作为无 JS 降级路径）---
  get '/ai_protocols/new', to: 'protocol_generator#new', as: :ai_protocol_new
  post '/ai_protocols/preview', to: 'protocol_generator#preview', as: :ai_protocol_preview
  post '/ai_protocols', to: 'protocol_generator#legacy_create', as: :ai_protocols

  # --- 新：官方形态弹窗用 JSON 接口（异步三段式，资源名 parsed_protocols）---
  #   POST   /parsed_protocols            -> create  (返回 {data:{id}})
  #   GET    /parsed_protocols/:id        -> show    (轮询：{data:{data:{attributes:{status,valid,parsed_data,last_error}}}})
  #   POST   /parsed_protocols/:id/import -> import  (落库为协议)
  #   GET    /parsed_protocols/remaining_count -> {data:{daily_limit,remaining_count}}
  resources :parsed_protocols, controller: 'protocol_generator', only: [:create, :show] do
    member do
      post :import
    end
    collection do
      get :remaining_count
    end
  end
end
