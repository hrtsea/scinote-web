# frozen_string_literal: true

# Injects the electronic-signature panel into the experiment show header.
# See app/overrides/protocol_header_esignature_panel.rb for the rationale.
# Result-level signing lives inside the Vue canvas and is handled separately
# (JS entry point), so only the Experiment entity is wired here.
Deface::Override.new(
  virtual_path: 'experiments/show_header',
  name: 'esignatures_experiment_panel',
  insert_after: 'div.content-header',
  text: '<% if Scinote::Esignatures.enabled? %><%= signature_panel_for(@experiment) %><% end %>',
  disabled: false
)
