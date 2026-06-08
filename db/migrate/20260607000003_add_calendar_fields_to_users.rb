class AddCalendarFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :access_level, :integer, default: 0, null: false
    add_column :users, :calendar_token, :string
    add_column :users, :calendar_needs_sync, :boolean, default: false, null: false
    add_column :users, :last_calendar_sync_at, :datetime
    add_column :users, :notifications_disabled_until, :datetime
    add_index :users, :access_level
    add_index :users, :calendar_token, unique: true
    add_index :users, :calendar_needs_sync
    add_index :users, :last_calendar_sync_at
  end
end
