# frozen_string_literal: true

# An OAuth client (Doorkeeper::Application) that the user let read their data
# through the MCP server. Pundit would look for Doorkeeper::ApplicationPolicy,
# so callers pass policy_class: ConnectedAppPolicy.
class ConnectedAppPolicy < ApplicationPolicy
  # The user can disconnect an app that holds one of their tokens.
  def destroy? = user.present? && Doorkeeper::Application.authorized_for(user).exists?(id: record.id)
end
