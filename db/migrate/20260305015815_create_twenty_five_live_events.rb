# frozen_string_literal: true

class CreateTwentyFiveLiveEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_events do |t|
      t.integer  :event_id,        null: false
      t.string   :event_locator,   null: false
      t.string   :event_name,      null: false
      t.string   :event_title
      t.date     :start_date
      t.date     :end_date
      t.integer  :event_type_id
      t.string   :event_type_name
      t.integer  :state
      t.string   :state_name
      t.integer  :cabinet_id
      t.string   :cabinet_name
      t.text     :description
      t.string   :registration_url
      t.boolean  :public_website,  default: false, null: false
      t.datetime :last_mod_dt
      t.datetime :creation_dt
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :twenty_five_live_events, :event_id,      unique: true
    add_index :twenty_five_live_events, :event_locator, unique: true
  end
end
