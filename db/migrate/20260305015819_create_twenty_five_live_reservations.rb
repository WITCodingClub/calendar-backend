# frozen_string_literal: true

class CreateTwentyFiveLiveReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_reservations do |t|
      t.references :twenty_five_live_event, null: false, foreign_key: true
      t.integer    :reservation_id,         null: false
      t.datetime   :event_start_dt
      t.datetime   :event_end_dt
      t.integer    :expected_count
      t.integer    :reservation_state

      t.timestamps
    end

    add_index :twenty_five_live_reservations, :reservation_id, unique: true
  end
end
