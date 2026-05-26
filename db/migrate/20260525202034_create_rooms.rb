# frozen_string_literal: true

class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string  :number,   null: false          # e.g. "010", "310"
      t.integer :floor,    null: false          # 0, 1, 2, 3, ...
      t.belongs_to :building, null: false, foreign_key: true

      t.timestamps
    end

    # Room identifier is unique within a building
    add_index :rooms,
              [:building_id, :number],
              unique: true,
              name: "index_rooms_on_building_id_and_number"

    # Floor must be non-negative
    add_check_constraint :rooms,
                         "floor >= 0",
                         name: "rooms_floor_non_negative"

    # First character of number must match floor (e.g. "310" → floor 3)
    add_check_constraint :rooms,
                         "substring(number from 1 for 1) = floor::text",
                         name: "rooms_floor_matches_number_prefix"
  end
end
