# SciNote I18n addon

Zero-intrusion multi-language support for SciNote.

## Features

- Locale resolution priority: **current user setting -> session -> browser language (Accept-Language) -> English**
- Per-user language persistence (stored in the existing `users.settings` hash)
- Frontend translation switching via the existing `i18n-js` asset pipeline
  (all available locales are exported to `translations.js`; missing keys fall back to English)
- Floating language switcher widget injected into every page (no view changes)
- Extensible: add a new language by adding a locale file + one entry in `lib/scinote/i18n.rb`

## Installation (host application)

Add the addon to the host `Gemfile`:

```ruby
gem 'scinote_i18n', path: 'addons/i18n'
```

Mount the engine in the host `config/routes.rb`:

```ruby
mount Scinote::I18n::Engine => '/'
```

Load the addon assets in the host `app/assets/javascripts/application.js.erb`:

```ruby
//= require scinote/i18n/application
```

Then run `bundle install`.

## Adding a new language

1. Add the locale file, e.g. `config/locales/de.yml`
2. Register it in `lib/scinote/i18n.rb` (`LOCALES`, `LANGUAGE_NAMES`)
3. Update the frontend list in `app/assets/javascripts/scinote/i18n/application.js` (`AVAILABLE_LOCALES`)
4. Recompile assets (`rails assets:precompile`)

## Layout

```
addons/i18n/
├── lib/scinote/i18n/engine.rb          # engine: locales, fallbacks, i18n-js config, decorators
├── app/decorators/
│   ├── controllers/application_controller_decorator.rb  # before_action :set_locale
│   └── models/user_decorator.rb                          # settings[:locale]
├── app/controllers/scinote/i18n/languages_controller.rb  # POST /users/settings/locale
├── app/assets/javascripts/scinote/i18n/application.js    # frontend glue + switcher
└── config/locales/en.yml, zh-CN.yml                      # translations
```
