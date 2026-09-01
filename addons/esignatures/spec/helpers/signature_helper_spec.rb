# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::Esignatures::SignatureHelper, type: :helper do
  let(:record) { build_stubbed(:experiment) }

  it 'renders the signature form when permitted' do
    allow(helper).to receive(:can_sign_record?).with(record).and_return(true)
    output = helper.signature_panel_for(record)
    expect(output).to include('esignature-form')
    expect(output).to include('name="meaning"')
    expect(output).to include(Scinote::Esignatures::SignatureHelper::SIGN_PATH)
  end

  it 'renders nothing when not permitted' do
    allow(helper).to receive(:can_sign_record?).with(record).and_return(false)
    expect(helper.signature_panel_for(record)).to eq(''.html_safe)
  end
end
