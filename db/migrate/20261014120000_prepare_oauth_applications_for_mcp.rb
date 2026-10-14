# frozen_string_literal: true

# The Doorkeeper tables are already in the schema from an earlier OAuth setup.
# MCP clients are public clients (PKCE, no secret) that register themselves,
# with POST /api/oauth/register (RFC 7591) or a client ID metadata document.
# dynamic marks those clients. See docs/mcp.md.
class PrepareOauthApplicationsForMcp < ActiveRecord::Migration[8.1]
  def change
    change_column_null :oauth_applications, :secret, true
    add_column :oauth_applications, :dynamic, :boolean, default: false, null: false
  end
end
