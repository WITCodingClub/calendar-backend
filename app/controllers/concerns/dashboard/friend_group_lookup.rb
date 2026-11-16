# frozen_string_literal: true

module Dashboard
  # The lookup of one of the user's own groups, for the dashboard friend group
  # controllers.
  module FriendGroupLookup
    extend ActiveSupport::Concern

    private

    # Scoping to the user's own groups is the access check: another user's group
    # id finds nothing.
    def find_group(public_id)
      group = policy_scope(FriendGroup).find_by_public_id(public_id)
      redirect_to dashboard_friends_path, alert: "Group not found." if group.nil?
      group
    end
  end
end
