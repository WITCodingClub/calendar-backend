# frozen_string_literal: true

class CreateTransferEquivalencies < ActiveRecord::Migration[8.1]
  def change
    create_table :transfer_equivalencies do |t|
      t.references :transfer_course, null: false, foreign_key: true
      t.references :wit_course, null: false, foreign_key: { to_table: :courses }
      t.date :effective_date, null: false
      t.date :expiration_date
      t.text :notes

      t.timestamps
    end

    add_index :transfer_equivalencies, [:transfer_course_id, :wit_course_id], unique: true, name: "idx_transfer_equivalencies_unique"
    add_index :transfer_equivalencies, :effective_date
    add_index :transfer_equivalencies, :expiration_date
  end

end
