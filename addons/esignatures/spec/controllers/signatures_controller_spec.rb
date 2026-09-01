# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scinote::Esignatures::SignaturesController, type: :controller do
  routes { Scinote::Esignatures::Engine.routes }

  let(:user) { create(:user, confirmed_at: Time.zone.now) }
  let(:experiment) { create(:experiment) }

  before { sign_in user }

  it 'creates a signature when permitted' do
    allow(Scinote::Esignatures::SignaturePolicy).to receive(:permits?).and_return(true)
    expect do
      post :create, params: { signable_type: 'Experiment', signable_id: experiment.id, meaning: 'approve' }
    end.to change(Scinote::Esignatures::ESignatureRecord, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)['signature_hash']).to be_present
  end

  it 'returns 403 when not permitted' do
    allow(Scinote::Esignatures::SignaturePolicy).to receive(:permits?).and_return(false)
    post :create, params: { signable_type: 'Experiment', signable_id: experiment.id, meaning: 'approve' }
    expect(response).to have_http_status(:forbidden)
  end

  it 'returns 422 when meaning is blank' do
    allow(Scinote::Esignatures::SignaturePolicy).to receive(:permits?).and_return(true)
    post :create, params: { signable_type: 'Experiment', signable_id: experiment.id, meaning: '' }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'returns 404 for a missing record' do
    allow(Scinote::Esignatures::SignaturePolicy).to receive(:permits?).and_return(true)
    post :create, params: { signable_type: 'Experiment', signable_id: 0, meaning: 'x' }
    expect(response).to have_http_status(:not_found)
  end
end
