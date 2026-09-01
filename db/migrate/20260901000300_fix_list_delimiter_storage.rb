# frozen_string_literal: true

# Follow-up fix for the list delimiter storage (part of the i18n cleanup).
#
# Predefined templates used to store the list delimiter as an i18n key
# ("repository_templates.repository_list_value_delimiter") and the create flow
# localized it to the viewer's locale at inventory-creation time. That froze the
# delimiter in whatever locale was active then, and — worse — for non-English
# locales the localized value (e.g. zh-CN "返回") is not a valid delimiter
# symbol, so Constants::REPOSITORY_LIST_ITEMS_DELIMITERS_MAP[delimiter.to_sym]
# misses and the list falls back to a newline / breaks editing.
#
# The delimiter is a fixed symbol ('return' / 'comma' / ...), never localized.
# This migration normalizes any already-stored, locale-localized delimiter value
# back to the canonical 'return' symbol.
class FixListDelimiterStorage < ActiveRecord::Migration[7.2]
  DELIMITER_I18N_KEY = 'repository_templates.repository_list_value_delimiter'
  CANONICAL = 'return'

  def up
    locales = I18n.available_locales
    translated = locales.map { |locale| I18n.t(DELIMITER_I18N_KEY, locale: locale) }

    RepositoryColumn.where.not(metadata: nil).find_each do |column|
      delimiter = column.metadata['delimiter']
      next unless delimiter.is_a?(String)
      next if delimiter == CANONICAL
      next unless translated.include?(delimiter)

      metadata = column.metadata.dup
      metadata['delimiter'] = CANONICAL
      column.update_columns(metadata: metadata)
    end
  end

  def down
    # The original localized value cannot be recovered reliably, and 'return' is a
    # valid delimiter symbol, so this is left as a no-op reversal of the schema
    # version only.
  end
end
