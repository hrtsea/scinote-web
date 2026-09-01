# frozen_string_literal: true

# Rails derives the migration class name from the filename, so it has to stay
# top-level and camel-case-match `..._scinote_esignatures_create_tables`.
# Installed into the host `db/migrate` (standard Rails engine pattern) so it is
# discoverable by `db:migrate` / `db:migrate:status`. Originates from the
# scinote_esignatures addon.
class ScinoteEsignaturesCreateTables < ActiveRecord::Migration[7.2]
  def change
    create_table :e_signatures do |t|
      t.references :team, null: false, foreign_key: true
      t.boolean :require_meaning, default: true, null: false
      t.boolean :require_second_factor, default: false, null: false
      t.timestamps
    end

    create_table :e_signature_records do |t|
      t.references :user, null: false, foreign_key: true
      t.string :signable_type, null: false
      t.bigint :signable_id, null: false
      t.text :meaning, null: false
      t.string :record_hash, null: false
      t.string :signature_hash, null: false
      t.string :previous_hash, null: false, default: '0'
      t.datetime :signed_at, null: false
      t.timestamps
    end

    add_index :e_signature_records, %i(signable_type signable_id)
  end
end
