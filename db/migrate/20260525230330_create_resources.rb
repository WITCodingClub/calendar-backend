# frozen_string_literal: true

class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_resources do |t|
      t.integer :twenty_five_live_id, null: false
      t.string  :name,                null: false
      t.integer :stock_level                        # nil = unlimited/N/A
      t.string  :assign_perm                        # R = requestable, X = not
      t.string  :schedule_perm                      # T/F

      t.timestamps
    end

    add_index :twenty_five_live_resources, :twenty_five_live_id, unique: true

    add_check_constraint :twenty_five_live_resources,
                         "length(trim(name)) > 0",
                         name: "twenty_five_live_resources_name_not_blank"
  end
end
