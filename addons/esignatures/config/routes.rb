# frozen_string_literal: true

Scinote::Esignatures::Engine.routes.draw do
  post '/esignatures/sign', to: 'signatures#create', as: :sign
end
