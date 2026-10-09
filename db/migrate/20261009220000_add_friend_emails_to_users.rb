# frozen_string_literal: true

# Lets a user turn off the friend emails: friend requests and friendship end
# date changes (#703). On by default, so nothing changes for current users.
class AddFriendEmailsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :friend_emails, :boolean, default: true, null: false
  end
end
