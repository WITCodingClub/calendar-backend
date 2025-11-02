class RefactorMeetingTimeToDayOfWeek < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Add day_of_week enum column (0=sunday, 1=monday, ..., 6=saturday)
    # Don't make it NOT NULL yet - we'll populate it in the next migration
    add_column :meeting_times, :day_of_week, :integer
    add_index :meeting_times, :day_of_week, algorithm: :concurrently
  end
end
