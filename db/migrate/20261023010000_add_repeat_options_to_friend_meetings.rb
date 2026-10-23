# frozen_string_literal: true

# More repeat options for a friend meeting (calendar-extension#227): every N
# days, weeks, or months, and more than one weekday for a weekly meeting. The
# defaults give each existing weekly meeting the same rule as before.
class AddRepeatOptionsToFriendMeetings < ActiveRecord::Migration[8.1]
  def change
    add_column :friend_meetings, :repeat_interval, :integer, default: 1, null: false
    add_column :friend_meetings, :repeat_days, :string, array: true, default: [], null: false
  end
end
