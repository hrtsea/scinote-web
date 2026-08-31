# frozen_string_literal: true

# Follow-up fix for LocalizeExistingRepositoryColumns (20260901000100).
#
# That migration rewrote every repository column / list / status value whose
# stored string equaled a predefined-template English translation back to an
# i18n key. Because it matched by *value* (not by origin), it also corrupted
# user-defined columns that happen to share the same English text — e.g. a
# custom column literally named "Notes" or "Stock" would be wrongly turned into
# a key and start following the viewer's locale.
#
# This migration restores only the affected user-defined data (repositories NOT
# created from a predefined template) back to their English strings, leaving
# predefined-template data as keys.
class FixLocalizeExistingRepositoryColumnsScope < ActiveRecord::Migration[7.2]
  PREDEFINED = %i[default cell_lines equipment chemicals_and_reagents].freeze

  def up
    reverse = reverse_map.invert
    return if reverse.empty?

    predefined_repo_ids = Repository.joins(:repository_template)
                                     .where(repository_templates: { predefined: true })
                                     .distinct.pluck(:id)
    return if predefined_repo_ids.empty?

    restore_scope(RepositoryColumn, :name, reverse, predefined_repo_ids, :repository)
    restore_scope(RepositoryListItem, :data, reverse, predefined_repo_ids, repository_column: :repository)
    restore_scope(RepositoryStatusItem, :status, reverse, predefined_repo_ids, repository_column: :repository)
  end

  def down
    reverse = reverse_map.invert
    return if reverse.empty?

    predefined_repo_ids = Repository.joins(:repository_template)
                                     .where(repository_templates: { predefined: true })
                                     .distinct.pluck(:id)
    return if predefined_repo_ids.empty?

    rekey_scope(RepositoryColumn, :name, reverse, predefined_repo_ids, :repository)
    rekey_scope(RepositoryListItem, :data, reverse, predefined_repo_ids, repository_column: :repository)
    rekey_scope(RepositoryStatusItem, :status, reverse, predefined_repo_ids, repository_column: :repository)
  end

  private

  # Restore user-defined rows (not from a predefined template) whose value is a
  # key back to its English translation.
  def restore_scope(model, column, reverse, predefined_repo_ids, join_chain)
    model.joins(join_chain)
         .where.not(repositories: { id: predefined_repo_ids })
         .where(column => reverse.keys)
         .find_each do |record|
      raw = record.read_attribute(column)
      record.update_columns(column => reverse.fetch(raw)) if reverse.key?(raw)
    end
  end

  # Undo restore_scope: re-write the English strings of non-predefined rows back
  # to keys (mirrors the original corruption so the pair is reversible).
  def rekey_scope(model, column, reverse, predefined_repo_ids, join_chain)
    model.joins(join_chain)
         .where.not(repositories: { id: predefined_repo_ids })
         .where(column => reverse.values)
         .find_each do |record|
      raw = record.read_attribute(column)
      record.update_columns(column => reverse.key(raw)) if reverse.value?(raw)
    end
  end

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
