# frozen_string_literal: true

class CreateEventCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_event_categories do |t|
      t.integer :twenty_five_live_id, null: false
      t.string  :name,                null: false
      t.integer :sort_order
      t.integer :defn_state,          null: false, default: 1

      t.timestamps
    end

    add_index :twenty_five_live_event_categories, :twenty_five_live_id, unique: true
  end
end
