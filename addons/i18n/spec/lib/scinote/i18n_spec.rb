# frozen_string_literal: true

require 'rails_helper'
require 'scinote/i18n'

# Smoke spec for the i18n addon's public API. Kept free of DB / view / controller
# dependencies so it runs reliably in the test environment (no devise confirmable
# mail, no webpacker manifest, no deface view rendering).
RSpec.describe Scinote::I18n do
  describe '.available_locales' do
    it 'exposes the bundled locales en and zh-CN' do
      expect(described_class.available_locales).to contain_exactly(:en, :'zh-CN')
    end
  end

  describe '.language_name' do
    it 'maps a known locale to its display name' do
      expect(described_class.language_name(:en)).to eq('English')
      expect(described_class.language_name(:'zh-CN')).to eq('简体中文')
    end

    it 'falls back to the locale string for unknown locales' do
      expect(described_class.language_name(:de)).to eq('de')
    end
  end
end
