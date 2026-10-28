# frozen_string_literal: true

module Api
  # The flag gate that every friend group controller shares. Include it after
  # authenticate_with_token, so the token check runs first.
  module FriendGroupsFlag
    extend ActiveSupport::Concern

    included do
      before_action :require_friend_groups
    end

    private

    def require_friend_groups
      return if FriendGroup.enabled_for?(current_user)

      render_error "Friend groups are not enabled", status: :not_found
    end
  end
end
