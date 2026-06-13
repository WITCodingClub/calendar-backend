# frozen_string_literal: true

class AddTwentyFiveLiveSpaceFieldsToBuildingsAndRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :buildings, :twenty_five_live_id, :integer
    add_column :buildings, :formal_name, :string
    add_index  :buildings, :twenty_five_live_id, unique: true,
               name: "index_buildings_on_twenty_five_live_id"

    add_column :rooms, :twenty_five_live_id, :integer
    add_column :rooms, :formal_name, :string
    add_index  :rooms, :twenty_five_live_id, unique: true,
               name: "index_rooms_on_twenty_five_live_id"
  end
end
