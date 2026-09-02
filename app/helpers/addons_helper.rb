module AddonsHelper
  # NOTE: `render_addon_config_field` / `render_addon_config_input` moved to the
  # `addons/addon_settings` addon (Scinote::AddonSettings::AddonsHelper). This
  # core helper keeps only `list_all_addons`, which is consumed by
  # config/initializers/load_addons_specs.rb and the addon discovery mechanism.
  def list_all_addons
    Rails::Engine
      .subclasses
      .select { |c| c.name.start_with?('Scinote') }
      .map(&:module_parent)
  end
end
