# frozen_string_literal: true

# Predefined repository templates used to store already-translated strings
# (localized at seed / team-creation time). This froze them in whatever locale
# was active then, so a zh-CN user could see English column names. We now store
# i18n keys and translate at render/apply time (see RepositoryTemplate). This
# migration rewrites the existing predefined templates to keys.
#
# It also repairs a data corruption introduced by
# UpdateRepositoryTemplateDateReminderValues (20250717131344), which copied the
# equipment template's column_definitions onto the chemicals template.
class LocalizePredefinedRepositoryTemplates < ActiveRecord::Migration[7.2]
  TEMPLATES = {
    'repository_templates.default_template_name' => :default,
    'repository_templates.cell_lines_template_name' => :cell_lines,
    'repository_templates.equipment_template_name' => :equipment,
    'repository_templates.chemicals_and_reagents_template_name' => :chemicals_and_reagents
  }.freeze

  def up
    TEMPLATES.each do |name_key, method|
      candidate_names = I18n.available_locales.map { |locale| I18n.t(name_key, locale: locale) }
      RepositoryTemplate.where(predefined: true, name: candidate_names).find_each do |template|
        predefined = RepositoryTemplate.public_send(method)
        template.update!(name: predefined.name, column_definitions: predefined.column_definitions)
      end
    end
  end

  def down
    TEMPLATES.each do |name_key, method|
      RepositoryTemplate.where(predefined: true, name: name_key).find_each do |template|
        predefined = RepositoryTemplate.public_send(method)
        I18n.with_locale(:en) do
          template.update!(
            name: I18n.t(name_key),
            column_definitions: RepositoryTemplate.localize_column_definitions(predefined.column_definitions)
          )
        end
      end
    end
  end
end
