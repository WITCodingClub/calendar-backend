# frozen_string_literal: true

# One row for each one-time catch-up run that the extension finished for a
# student, such as processing past terms after the v6 upgrade
# (WITCodingClub/calendar-extension#215).
class CreateUserBackfills < ActiveRecord::Migration[8.1]
  def change
    create_table :user_backfills do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.datetime :completed_at, null: false
      t.timestamps
    end

    add_index :user_backfills, [ :user_id, :name ], unique: true
  end
end
