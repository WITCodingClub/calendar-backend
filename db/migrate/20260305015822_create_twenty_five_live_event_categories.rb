# frozen_string_literal: true

class CreateTwentyFiveLiveEventCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_event_categories do |t|
      t.references :twenty_five_live_event,    null: false, foreign_key: true
      t.references :twenty_five_live_category, null: false, foreign_key: true

      t.timestamps
    end

    add_index :twenty_five_live_event_categories,
              %i[twenty_five_live_event_id twenty_five_live_category_id],
              unique: true,
              name: "index_tfl_event_cats_on_event_and_cat"
  end
end
