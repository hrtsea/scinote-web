# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Addon settings management', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin_user) { create(:user, confirmed_at: Time.zone.now) }
  let(:normal_user) { create(:user, confirmed_at: Time.zone.now) }

  # In this environment Rails.configuration.x.enable_email_confirmations resolves to
  # a truthy OrderedOptions default (the config.x reader returns a fresh object for
  # unset keys), so Devise fires a confirmation email on every user creation. That
  # email fails at deliver_later because no SMTP sender is configured in tests.
  # Neutralize the Devise notification at the instance-method level for the whole
  # example group. This must run before the `around` block creates the users below.
  before(:all) do
    User.__send__(:define_method, :send_devise_notification) { |*_args| true }
  end

  around do |example|
    original = ApplicationSettings.instance.values['instance_admin_user_ids']

    ApplicationSettings.instance.update(
      values: ApplicationSettings.instance.values.merge('instance_admin_user_ids' => [admin_user.id])
    )

    example.run

    if original.nil?
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.except('instance_admin_user_ids')
      )
    else
      ApplicationSettings.instance.update(
        values: ApplicationSettings.instance.values.merge('instance_admin_user_ids' => original)
      )
    end
  end

  describe 'PUT /users/settings/account/addons/:name' do
    context 'as an instance administrator' do
      it 'persists enabled flag and configuration' do
        sign_in admin_user

        put update_addon_path('esignatures'),
            params: { enabled: 'false', configuration: '{"require_meaning":false}' }

        expect(response).to redirect_to(addons_path)

        expect(AddonSetting.enabled?('esignatures')).to be false

        expect(AddonSetting.for('esignatures').configuration).to eq({ 'require_meaning' => false })
      end

      context 'with a schema-driven configuration form' do
        it 'stores typed values declared by the addon config_schema' do
          sign_in admin_user

          put update_addon_path('ai_protocols'),
              params: {
                enabled: 'true',
                configuration: { parser_url: 'https://parser.test/v1', model: 'gpt-4o' }
              }

          expect(response).to redirect_to(addons_path)

          config = AddonSetting.for('ai_protocols').configuration

          expect(config['parser_url']).to eq('https://parser.test/v1')
          expect(config['model']).to eq('gpt-4o')
        end

        it 'casts boolean fields and turns the flag off when unchecked' do
          sign_in admin_user

          AddonSetting.update_for('esignatures', enabled: true,
                                  configuration: { require_intent: true })

          put update_addon_path('esignatures'),
              params: { enabled: 'true', configuration: { require_intent: '0' } }

          expect(AddonSetting.for('esignatures').configuration['require_intent']).to be false
        end

        it 'keeps the existing secret when the field is submitted blank' do
          sign_in admin_user

          AddonSetting.update_for('ai_protocols', enabled: true,
                                  configuration: { api_key: 'previous-secret' })

          put update_addon_path('ai_protocols'),
              params: { enabled: 'true', configuration: { api_key: '' } }

          expect(AddonSetting.for('ai_protocols').configuration['api_key']).to eq('previous-secret')
        end
      end
    end

    context 'as an instance administrator with invalid configuration' do
      it 'redirects with an error and does not persist the invalid JSON' do
        sign_in admin_user

        put update_addon_path('esignatures'),
            params: { enabled: 'true', configuration: 'not-json' }

        expect(response).to redirect_to(addons_path)

        expect(flash[:alert]).to eq(I18n.t('users.settings.account.addons.update_error'))

        expect(AddonSetting.for('esignatures').configuration).to eq({})
      end
    end

    context 'as an instance administrator submitting an out-of-range integer' do
      it 'rejects the update and keeps the previous configuration' do
        sign_in admin_user

        AddonSetting.update_for('project_insights', enabled: true, configuration: { default_period_days: 90 })

        put update_addon_path('project_insights'),
            params: { enabled: 'true', configuration: { default_period_days: '-5' } }

        expect(response).to redirect_to(addons_path)

        expect(flash[:alert]).to eq(I18n.t('users.settings.account.addons.update_error'))

        expect(AddonSetting.for('project_insights').configuration['default_period_days']).to eq(90)
      end
    end

    context 'for a non-disablable addon' do
      it 'ignores a disable attempt and keeps it enabled' do
        sign_in admin_user

        put update_addon_path('addon_settings'), params: { enabled: 'false' }

        expect(response).to redirect_to(addons_path)
        expect(AddonSetting.enabled?('addon_settings')).to be true
      end
    end

    context 'as a non-admin user' do
      it 'is forbidden' do
        sign_in normal_user

        put update_addon_path('esignatures'), params: { enabled: 'false' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not signed in' do
      it 'redirects to the login page' do
        put update_addon_path('esignatures'), params: { enabled: 'false' }

        expect(response).to redirect_to(%r{/users/sign_in|/users/login})
      end
    end

    context 'with an unknown addon name' do
      it 'returns not found' do
        sign_in admin_user

        put update_addon_path('does_not_exist'),
            params: { enabled: 'true', configuration: {} }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /users/settings/account/addons' do
    it 'renders a configure link per addon for an admin' do
      sign_in admin_user

      get addons_path

      expect(response).to have_http_status(:success)

      expect(response.body).to include(edit_addon_path('esignatures'))
    end

    it 'renders the page without management controls for a regular user' do
      sign_in normal_user

      get addons_path

      expect(response).to have_http_status(:success)

      expect(response.body).not_to include(edit_addon_path('esignatures'))
    end

    # Regression: the settings page must be rendered by the addon's own view
    # (distinct `use-account-addons` wrapper), NOT a residual core view
    # (`user-account-addons`). The core app/views path takes precedence over the
    # engine view path, so a leftover core view would silently shadow the addon.
    it 'renders the addon-owned view rather than a residual core view' do
      sign_in admin_user

      get addons_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('use-account-addons')
    end

    it 'renders each addon description for an admin' do
      sign_in admin_user

      get addons_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t('project_insights.settings.description'))
    end

    it 'does not render an inline enable checkbox on the index' do
      sign_in admin_user

      get addons_path

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('name="enabled"')
    end
  end

  describe 'GET /users/settings/account/addons/:name (edit)' do
    it 'renders the config form for an admin' do
      sign_in admin_user

      get edit_addon_path('project_insights')

      expect(response).to have_http_status(:success)
      expect(response.body).to include(update_addon_path('project_insights'))
      expect(response.body).to include('name="configuration[default_period_days]"')
    end

    it 'is forbidden for a non-admin user' do
      sign_in normal_user

      get edit_addon_path('esignatures')

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns not found for an unknown addon name' do
      sign_in admin_user

      get edit_addon_path('does_not_exist')

      expect(response).to have_http_status(:not_found)
    end

    it 'disables config fields when the addon is disabled' do
      sign_in admin_user

      AddonSetting.update_for('project_insights', enabled: false, configuration: {})

      get edit_addon_path('project_insights')

      expect(response).to have_http_status(:success)

      expect(response.body).to include('name="configuration[default_period_days]"')

      expect(response.body).to include('disabled="disabled"')
    end

    it 'shows a "set" indicator for a stored secret field' do
      sign_in admin_user

      AddonSetting.update_for('ai_protocols', enabled: true, configuration: { api_key: 'topsecret' })

      get edit_addon_path('ai_protocols')

      expect(response).to have_http_status(:success)

      expect(response.body).to include(I18n.t('users.settings.account.addons.config_secret_set'))
    end

    it 'renders the addon-owned edit view rather than a residual core view' do
      sign_in admin_user

      get edit_addon_path('esignatures')

      expect(response).to have_http_status(:success)
      expect(response.body).to include('use-account-addons-edit')
    end

    it 'renders the detailed help text for an admin' do
      sign_in admin_user

      get edit_addon_path('project_insights')

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t('project_insights.settings.detailed_help'))
    end

    it 'hides the enable toggle for a non-disablable addon' do
      sign_in admin_user

      get edit_addon_path('addon_settings')

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('name="enabled"')
      expect(response.body).to include(I18n.t('users.settings.account.addons.always_enabled'))
    end

    it 'renders the enable toggle for a disablable addon' do
      sign_in admin_user

      get edit_addon_path('esignatures')

      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="enabled"')
    end
  end
end
