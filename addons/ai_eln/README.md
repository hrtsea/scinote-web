# SciNote addon - `ai_eln`

## How to include this addon inside main SciNote application

* Inside `Gemfile`, add the following reference:

```ruby
gem 'scinote_ai_eln',
    path: 'addons/ai_eln'
```

* Inside `config/routes.rb`, add the following reference:

```ruby
mount Scinote::AiEln::Engine => '/ai_eln'
```

* If you have any addon-specific JavaScript code, add the following reference inside `app/assets/javascripts/application.js.erb`:

```js
//= require scinote/ai_eln
```

* If you have any addon-specific CSS code, add the following reference inside `app/assets/stylesheets/application.scss` (starting comment):

```css
 *= require scinote/ai_eln/application
```

Then, do the following:

1. Run `make docker`,
2. Run `make cli` -> `rake db:migrate`,
3. (optional) setup any addon initializers/settings,
4. Start application (`make run`)!
