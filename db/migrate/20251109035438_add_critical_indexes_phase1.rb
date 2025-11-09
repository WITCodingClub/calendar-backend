# frozen_string_literal: true

class AddCriticalIndexesPhase1 < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Critical: Email lookups on every login/OAuth flow
    # User.find_or_create_by_email and User.find_by_email perform email lookups
    # Without this index, these operations require full table scans
    add_index :emails, :email, unique: true, if_not_exists: true, algorithm: :concurrently

    # High Priority: OAuth token expiration checks in DeleteOrphanedGoogleCalendarsJob
    # Filters by token_expires_at to find expired tokens
    add_index :oauth_credentials, :token_expires_at, if_not_exists: true, algorithm: :concurrently
  end
end
