# frozen_string_literal: true

class AddNotificationsDisabledUntilToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notifications_disabled_until, :datetime
    add_index :users, :notifications_disabled_until
  end
end
