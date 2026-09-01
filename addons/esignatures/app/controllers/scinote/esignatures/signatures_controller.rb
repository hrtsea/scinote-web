# frozen_string_literal: true

module Scinote
  module Esignatures
    # Handles the electronic-signature action invoked from core views via the
    # decorator-injected button. Never mutates the signed record; it only appends
    # an immutable ESignatureRecord through SignatureService.
    class SignaturesController < ::ApplicationController
      include Scinote::Esignatures::SignatureGate

      SIGN_ABLE_TYPES = %w(Protocol Result Experiment).freeze

      before_action :set_signable, only: [:create]

      def create
        return render_forbidden unless can_sign_record?(@signable)

        record = SignatureService.call(
          record: @signable,
          user: current_user,
          meaning: params[:meaning]
        )
        render json: { signature_id: record.id, signature_hash: record.signature_hash },
               status: :created
      rescue SignatureService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_signable
        return render(json: { error: 'unsupported signable type' }, status: :unprocessable_entity) \
          unless SIGN_ABLE_TYPES.include?(params[:signable_type])

        klass = params[:signable_type].constantize
        @signable = klass.find_by(id: params[:signable_id])
        return render(json: { error: 'record not found' }, status: :not_found) if @signable.nil?
      end

      def render_forbidden
        render json: { error: 'forbidden' }, status: :forbidden
      end
    end
  end
end
