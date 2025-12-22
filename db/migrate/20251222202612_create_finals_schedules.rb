# frozen_string_literal: true

class CreateFinalsSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :finals_schedules do |t|
      t.references :term, null: false, foreign_key: true
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.datetime :processed_at
      t.text :error_message
      t.jsonb :stats, default: {}

      t.timestamps
    end

    add_index :finals_schedules, [:term_id, :created_at]
  end
end
