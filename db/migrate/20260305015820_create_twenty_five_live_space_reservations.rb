# frozen_string_literal: true

class CreateTwentyFiveLiveSpaceReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_space_reservations do |t|
      t.references :twenty_five_live_reservation, null: false, foreign_key: true
      t.references :twenty_five_live_space,        null: false, foreign_key: true
      t.integer    :layout_id
      t.string     :layout_name
      t.integer    :selected_layout_capacity

      t.timestamps
    end
  end
end
