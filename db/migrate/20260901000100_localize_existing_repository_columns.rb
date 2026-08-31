# frozen_string_literal: true

# Predefined repository template columns used to store already-translated
# strings (frozen at seed / inventory-creation time) in repository_columns.name
# and repository_list_items.data / repository_status_items.status. This froze
# them in whatever locale was active then, so a zh-CN user could see English
# column names / list values. Names / list / status values are now stored as
# i18n keys and localized at read time (see RepositoryColumn#name,
# RepositoryListItem#data, RepositoryStatusItem#status). This migration rewrites
# the existing predefined-template data back to keys.
class LocalizeExistingRepositoryColumns < ActiveRecord::Migration[7.2]
  PREDEFINED = %i[default cell_lines equipment chemicals_and_reagents].freeze

  def up
    map = reverse_map
    return if map.empty?

    keys = map.keys
    RepositoryColumn.where(name: keys).find_each do |column|
      raw = column.read_attribute(:name)
      column.update_columns(name: map.fetch(raw)) if map.key?(raw)
    end
    RepositoryListItem.where(data: keys).find_each do |item|
      raw = item.read_attribute(:data)
      item.update_columns(data: map.fetch(raw)) if map.key?(raw)
    end
    RepositoryStatusItem.where(status: keys).find_each do |status_item|
      raw = status_item.read_attribute(:status)
      status_item.update_columns(status: map.fetch(raw)) if map.key?(raw)
    end
  end

  def down
    map = reverse_map
    return if map.empty?

    values = map.values
    RepositoryColumn.where(name: values).find_each do |column|
      english = map.key(column.read_attribute(:name))
      column.update_columns(name: english) if english
    end
    RepositoryListItem.where(data: values).find_each do |item|
      english = map.key(item.read_attribute(:data))
      item.update_columns(data: english) if english
    end
    RepositoryStatusItem.where(status: values).find_each do |status_item|
      english = map.key(status_item.read_attribute(:status))
      status_item.update_columns(status: english) if english
    end
  end

  private

  def reverse_map
    map = {}
    PREDEFINED.each do |method|
      template = RepositoryTemplate.public_send(method)
      next if template.column_definitions.blank?

      template.column_definitions.each do |column|
        add_entry(map, column.dig('params', 'name'))
        Array(column.dig('params', 'repository_list_items_attributes')).each do |item|
          add_entry(map, item['data'])
        end
        Array(column.dig('params', 'repository_status_items_attributes')).each do |item|
          add_entry(map, item['status'])
        end
      end
    end
    map
  end

  def add_entry(map, value)
    return unless value.is_a?(String) && value.start_with?(RepositoryTemplate::TEMPLATE_I18N_PREFIX)

    map[I18n.t(value, locale: :en)] = value
  end
end
