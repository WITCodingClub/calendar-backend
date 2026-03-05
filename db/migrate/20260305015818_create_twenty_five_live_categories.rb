# frozen_string_literal: true

class CreateTwentyFiveLiveCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_categories do |t|
      t.integer :category_id,   null: false
      t.string  :category_name

      t.timestamps
    end

    add_index :twenty_five_live_categories, :category_id, unique: true
  end
end
