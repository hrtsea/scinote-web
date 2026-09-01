# frozen_string_literal: true

Scinote::AiProtocols::Engine.routes.draw do
  get '/ai_protocols/new', to: 'protocol_generator#new', as: :ai_protocol_new
  post '/ai_protocols/preview', to: 'protocol_generator#preview', as: :ai_protocol_preview
  post '/ai_protocols', to: 'protocol_generator#create', as: :ai_protocols
end
