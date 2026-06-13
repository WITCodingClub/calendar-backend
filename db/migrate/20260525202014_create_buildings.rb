# frozen_string_literal: true

class CreateBuildings < ActiveRecord::Migration[8.1]
  def change
    create_table :buildings do |t|
      t.string :abbreviation, null: false  # "WENTW"
      t.string :name,         null: false  # "Wentworth Hall"

      t.timestamps
    end

    add_index :buildings, :abbreviation, unique: true
    add_index :buildings, :name,         unique: true

    add_check_constraint :buildings,
                         "length(trim(abbreviation)) > 0 AND length(trim(name)) > 0",
                         name: "buildings_abbreviation_and_name_not_blank"
  end
end
