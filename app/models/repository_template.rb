# frozen_string_literal: true

class RepositoryTemplate < ApplicationRecord
  belongs_to :team, inverse_of: :repository_templates
  has_many :repositories, inverse_of: :repository_template, dependent: :nullify

  # Predefined template strings are stored as i18n keys (not pre-translated
  # values) so they can be localized for the *current* user locale at render /
  # apply time. This keeps the same template correct for every locale instead of
  # freezing the language active when the template was first seeded.
  TEMPLATE_I18N_PREFIX = 'repository_templates.'

  def self.default
    RepositoryTemplate.new(
      name: 'repository_templates.default_template_name',
      column_definitions: [],
      predefined: true
    )
  end

  def self.cell_lines
    RepositoryTemplate.new(
      name: 'repository_templates.cell_lines_template_name',
      column_definitions: [
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.species' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.organ' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryListValue],
          params: { name: 'repository_templates.template_columns.morphology',
                    metadata: { delimiter: 'repository_templates.repository_list_value_delimiter' },
                    repository_list_items_attributes: [{ data: 'repository_templates.template_columns.repository_list_value.endothelial' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.epithelial' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.fibroblast' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.lymphoblast' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryListValue],
          params: { name: 'repository_templates.template_columns.culture_type',
                    metadata: { delimiter: 'repository_templates.repository_list_value_delimiter' },
                    repository_list_items_attributes: [{ data: 'repository_templates.template_columns.repository_list_value.adherent' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.suspension' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryStockValue],
          params: { name: 'repository_templates.template_columns.stock',
                    metadata: { decimals: 2 },
                    repository_stock_unit_items_attributes: RepositoryStockUnitItem::DEFAULT_UNITS.map { |unit| { data: unit } } +
                                                            [{ data: 'repository_templates.template_columns.stock_units.vials' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryNumberValue],
          params: { name: 'repository_templates.template_columns.passage_number' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.lot_number' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryDateValue],
          params: { name: 'repository_templates.template_columns.freezing_date' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.operator' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.yield' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryStatusValue],
          params: { name: 'repository_templates.template_columns.status',
                    repository_status_items_attributes: [{ status: 'repository_templates.template_columns.repository_status_value.frozen', icon: '❄️' },
                                                         { status: 'repository_templates.template_columns.repository_status_value.in_subculturing', icon: '🧫' },
                                                         { status: 'repository_templates.template_columns.repository_status_value.out_of_tock', icon: '❌' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryAssetValue],
          params: { name: 'repository_templates.template_columns.handling_procedure' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.notes' }
        }
      ],
      predefined: true
    )
  end

  def self.equipment
    RepositoryTemplate.new(
      name: 'repository_templates.equipment_template_name',
      column_definitions: [
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryDateValue],
          params: { name: 'repository_templates.template_columns.calibration_date',
                    reminder_value: '1', reminder_unit: '2419200', reminder_message: 'repository_templates.template_columns.calibration_message' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryStatusValue],
          params: { name: 'repository_templates.template_columns.availability_status',
                    repository_status_items_attributes: [{ status: 'repository_templates.template_columns.repository_status_value.available_for_use', icon: '🟢' },
                                                         { status: 'repository_templates.template_columns.repository_status_value.in_use', icon: '🟥' },
                                                         { status: 'repository_templates.template_columns.repository_status_value.out_of_service', icon: '❌' },
                                                         { status: 'repository_templates.template_columns.repository_status_value.under_maintenance', icon: '🔧' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryAssetValue],
          params: { name: 'repository_templates.template_columns.safety_handling_info' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryAssetValue],
          params: { name: 'repository_templates.template_columns.training_records' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.contact_person' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.contact_phone' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.internal_id' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.manufacturer' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.serial_number' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.notes' }
        }
      ],
      predefined: true
    )
  end

  def self.chemicals_and_reagents
    RepositoryTemplate.new(
      name: 'repository_templates.chemicals_and_reagents_template_name',
      column_definitions: [
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.concentration' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryStockValue],
          params: { name: 'repository_templates.template_columns.stock',
                    metadata: { decimals: 2 },
                    repository_stock_unit_items_attributes: RepositoryStockUnitItem::DEFAULT_UNITS.map { |unit| { data: unit } } }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryDateValue],
          params: { name: 'repository_templates.template_columns.date_opened' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryDateValue],
          params: { name: 'repository_templates.template_columns.expiration_date',
                    reminder_value: '1', reminder_unit: '2419200', reminder_message: 'repository_templates.template_columns.expiration_date_message' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryListValue],
          params: { name: 'repository_templates.template_columns.storage_conditions',
                    metadata: { delimiter: 'repository_templates.repository_list_value_delimiter' },
                    repository_list_items_attributes: [{ data: 'repository_templates.template_columns.repository_list_value.minus_twenty_celsious' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.two_to_eigth_celsious' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.minus_eigthty' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.ambient' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryListValue],
          params: { name: 'repository_templates.template_columns.type',
                    metadata: { delimiter: 'repository_templates.repository_list_value_delimiter' },
                    repository_list_items_attributes: [{ data: 'repository_templates.template_columns.repository_list_value.buffer' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.liquid' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.reagent' },
                                                       { data: 'repository_templates.template_columns.repository_list_value.solid' }] }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.purity' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.cas_number' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryAssetValue],
          params: { name: 'repository_templates.template_columns.safety_sheet' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryListValue],
          params: { name: 'repository_templates.template_columns.vendor' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.catalog_number' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.lot' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.price' }
        },
        {
          column_type: Extends::REPOSITORY_DATA_TYPES[:RepositoryTextValue],
          params: { name: 'repository_templates.template_columns.molecular_weight' }
        }
      ],
      predefined: true
    )
  end

  # Translate a single predefined-template string. Values that are not i18n
  # keys (e.g. already-localized legacy data, or unit symbols like "L") are
  # returned unchanged so the helper is safe to call on partially-migrated data.
  def self.localize_value(value)
    return value unless value.is_a?(String) && value.start_with?(TEMPLATE_I18N_PREFIX)

    I18n.t(value)
  end

  # Localize a full column_definitions array (column names, list item values,
  # status values, list delimiter and reminder messages) for the current locale.
  def self.localize_column_definitions(definitions)
    return definitions if definitions.blank?

    definitions.map do |column|
      params = (column['params'] || column[:params] || {}).deep_dup

      params['name'] = localize_value(params['name']) if params['name'].is_a?(String)

      if params['repository_list_items_attributes'].is_a?(Array)
        params['repository_list_items_attributes'] = params['repository_list_items_attributes'].map do |item|
          item = item.dup
          item['data'] = localize_value(item['data']) if item['data'].is_a?(String)
          item
        end
      end

      if params['repository_status_items_attributes'].is_a?(Array)
        params['repository_status_items_attributes'] = params['repository_status_items_attributes'].map do |item|
          item = item.dup
          item['status'] = localize_value(item['status']) if item['status'].is_a?(String)
          item
        end
      end

      if params['metadata'].is_a?(Hash)
        params['metadata']['delimiter'] = localize_value(params['metadata']['delimiter']) if params['metadata']['delimiter'].is_a?(String)
        params['metadata']['reminder_message'] = localize_value(params['metadata']['reminder_message']) if params['metadata']['reminder_message'].is_a?(String)
      end

      column.merge('params' => params)
    end
  end
end
