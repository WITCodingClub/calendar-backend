# frozen_string_literal: true

# Shared by the dashboard friend group controllers: the flag gate and the
# lookup of one of the user's own groups.
module Dashboard::FriendGroupLookup
  extend ActiveSupport::Concern

  included do
    before_action :require_friend_groups
  end

  private

  # A halted before_action skips verify_authorized, so the 404 needs no authorize.
  def require_friend_groups
    head :not_found unless FriendGroup.enabled_for?(current_user)
  end

  # Scoping to the user's own groups is the access check: another user's group
  # id finds nothing.
  def find_group(public_id)
    group = policy_scope(FriendGroup).find_by_public_id(public_id)
    redirect_to dashboard_friends_path, alert: "Group not found." if group.nil?
    group
  end
end
