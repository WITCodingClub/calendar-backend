# frozen_string_literal: true

# Stores the WIT email scraped from the user's authenticated WIT session as
# metadata (which student the account belongs to). NOT unique and NOT used for
# authentication/account resolution — the value is client-supplied and can't be
# verified server-side, so trusting it for identity would reopen the takeover.
# Indexed only for admin/support lookups.
class AddWitEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :wit_email, :string
    add_index :users, :wit_email
  end
end
