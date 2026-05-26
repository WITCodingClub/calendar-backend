# frozen_string_literal: true

class CreateEventCustomAttributes < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_event_custom_attributes do |t|
      t.integer :twenty_five_live_id,  null: false
      t.string  :name,                 null: false
      t.string  :attribute_type
      t.string  :attribute_type_name
      t.string  :multi_val
      t.integer :sort_order
      t.integer :defn_state,           null: false, default: 1

      t.timestamps
    end

    # twenty_five_live_id can be negative for system-defined attributes
    add_index :twenty_five_live_event_custom_attributes, :twenty_five_live_id, unique: true
  end
end
