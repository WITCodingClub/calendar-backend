# frozen_string_literal: true

class CreateTwentyFiveLiveSpaces < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_spaces do |t|
      t.integer :space_id,      null: false
      t.string  :space_name
      t.string  :formal_name
      t.string  :building_name
      t.integer :max_capacity

      t.timestamps
    end

    add_index :twenty_five_live_spaces, :space_id, unique: true
  end
end
