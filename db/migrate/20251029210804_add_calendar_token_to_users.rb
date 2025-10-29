class AddCalendarTokenToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :calendar_token, :string
    add_index :users, :calendar_token, unique: true, algorithm: :concurrently
  end
end