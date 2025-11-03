class AddCalendarNeedsSyncToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :calendar_needs_sync, :boolean, default: false, null: false
    add_column :users, :last_calendar_sync_at, :datetime
  end
end
