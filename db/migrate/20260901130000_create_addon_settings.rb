# frozen_string_literal: true

class CreateAddonSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :addon_settings do |t|
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :configuration, null: false, default: {}

      t.timestamps
    end

    add_index :addon_settings, :name, unique: true
  end
end
