# frozen_string_literal: true

# The OAuth tables for MCP clients (docs/mcp.md).
#
# db/schema.rb listed the Doorkeeper tables from an earlier OAuth setup, but
# no migration ever created them, so a database built from migrations (like
# production) does not have them. A database built from schema.rb does. This
# migration handles both: it creates each missing table, and changes
# oauth_applications where it already exists.
#
# MCP clients are public clients (PKCE, no secret) that register themselves,
# with POST /api/oauth/register (RFC 7591) or a client ID metadata document.
# dynamic marks those clients.
class PrepareOauthApplicationsForMcp < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:oauth_applications)
      change_column_null :oauth_applications, :secret, true
      add_column :oauth_applications, :dynamic, :boolean, default: false, null: false unless column_exists?(:oauth_applications, :dynamic)
    else
      create_table :oauth_applications do |t|
        t.string  :name,         null: false
        t.string  :uid,          null: false, index: { unique: true }
        t.string  :secret
        t.text    :redirect_uri, null: false
        t.string  :scopes,       null: false, default: ""
        t.boolean :confidential, null: false, default: true
        t.timestamps
        t.boolean :dynamic,      null: false, default: false
      end
    end

    unless table_exists?(:oauth_access_grants)
      create_table :oauth_access_grants do |t|
        t.references :resource_owner, null: false, foreign_key: { to_table: :users }
        t.references :application,    null: false, foreign_key: { to_table: :oauth_applications }
        t.string   :token,                 null: false, index: { unique: true }
        t.integer  :expires_in,            null: false
        t.text     :redirect_uri,          null: false
        t.string   :scopes,                null: false, default: ""
        t.string   :code_challenge
        t.string   :code_challenge_method
        t.datetime :created_at,            null: false
        t.datetime :revoked_at
      end
    end

    return if table_exists?(:oauth_access_tokens)

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, foreign_key: { to_table: :users }
      t.references :application,    null: false, foreign_key: { to_table: :oauth_applications }
      t.string   :token,                  null: false, index: { unique: true }
      t.string   :refresh_token,          index: { unique: true }
      t.integer  :expires_in
      t.string   :scopes
      t.datetime :created_at,             null: false
      t.datetime :revoked_at
      t.string   :previous_refresh_token, null: false, default: ""
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
