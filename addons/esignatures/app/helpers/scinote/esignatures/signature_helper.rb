# frozen_string_literal: true

module Scinote
  module Esignatures
    # View helper that renders the electronic-signature entry form, gated by the
    # `can_sign_record?` permission. Returns an empty safe string when the
    # current user may not sign, so core views can drop it in unconditionally.
    #
    # SIGN_PATH mirrors the engine route mounted at '/' (see config/routes.rb);
    # referenced literally to keep the helper usable in any view/helper context
    # without depending on the mounted-engine URL helper.
    module SignatureHelper
      include SignatureGate

      SIGN_PATH = '/esignatures/sign'

      def signature_panel_for(record)
        return ''.html_safe unless can_sign_record?(record)

        tag.div(class: 'esignature-panel',
                data: { signable_type: record.class.name, signable_id: record.id }) do
          form_with(url: SIGN_PATH, method: :post, local: true, class: 'esignature-form') do
            safe_join([
                        hidden_field_tag(:signable_type, record.class.name),
                        hidden_field_tag(:signable_id, record.id),
                        label_tag(:meaning, t('esignatures.signature.intent')),
                        text_field_tag(:meaning, '', required: Scinote::Esignatures.require_intent?,
                                       placeholder: t('esignatures.signature.intent_placeholder')),
                        submit_tag(t('esignatures.signature.sign'))
                      ])
          end
        end
      end
    end
  end
end
