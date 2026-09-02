# frozen_string_literal: true

require 'rails_helper'

# Locks in the deface-based UI entry points so a regression that drops the
# addon's app/overrides (or renames the targeted core partial) fails loudly.
# Actual markup/gating is covered by signature_helper_spec and the controller
# spec; here we only assert the overrides are wired into the right views.
RSpec.describe 'Scinote::Esignatures deface overrides' do
  subject { Deface::Override.all.keys }

  it 'injects the panel into the protocol show header' do
    expect(subject).to include(:'protocols/header')
  end

  it 'injects the panel into the experiment show header' do
    expect(subject).to include(:'experiments/show_header')
  end

  it 'guards the protocol panel injection behind the enabled? contract' do
    override = Deface::Override.all[:'protocols/header']['esignatures_protocol_panel']
    expect(override.args[:text]).to include('Scinote::Esignatures.enabled?')
  end
end
