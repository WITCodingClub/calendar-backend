# frozen_string_literal: true

class AddNotificationsDisabledUntilToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :notifications_disabled_until, :datetime
    add_index :users, :notifications_disabled_until, algorithm: :concurrently
  end
end
