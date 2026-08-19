# frozen_string_literal: true

class AddCapacityToRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :capacity, :integer

    add_check_constraint :rooms, "capacity IS NULL OR capacity > 0",
                         name: "rooms_capacity_positive"
  end
end
