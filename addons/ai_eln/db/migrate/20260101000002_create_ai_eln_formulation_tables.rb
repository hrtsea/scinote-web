# frozen_string_literal: true

class CreateAiElnFormulationTables < ActiveRecord::Migration[7.2]
  def change
    # 配方（组成定义，一等实体；ADR-0006 推翻原 glossary "无 recipes 表"）
    create_table :ai_eln_formulations do |t|
      t.references :team, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    # 配方组成项：成分(宿主 RepositoryRow) + 投料量；复用物料主数据（纯度/浓度/CAS 等）
    create_table :ai_eln_formulation_components do |t|
      t.references :formulation, null: false, foreign_key: { to_table: :ai_eln_formulations }
      t.references :repository_row, null: false
      t.decimal :amount, precision: 20, scale: 6, null: false
      t.string :unit, null: false
      t.timestamps
    end

    # 配方性质：实测值 + 目标值；my_module_id 指宿主实验任务实例（设计目标为 NULL，支持同配方多批次 S3）
    create_table :ai_eln_formulation_properties do |t|
      t.references :formulation, null: false, foreign_key: { to_table: :ai_eln_formulations }
      t.string :name, null: false
      t.decimal :measured_value, precision: 20, scale: 6
      t.string :measured_unit
      t.decimal :target_value, precision: 20, scale: 6
      t.string :comparator # '>=', '<=', '=', '>', '<'
      t.integer :my_module_id # 宿主 MyModule（实验实例）；设计目标为 NULL
      t.timestamps
    end

    add_index :ai_eln_formulation_components, %i[formulation_id repository_row_id],
              unique: true, name: "idx_formulation_components_uniq_row"
    add_index :ai_eln_formulation_properties, %i[formulation_id name]
  end
end
