# frozen_string_literal: true

module Dashboard
  # Shared by the dashboard friends controllers: the friends feature flags, the
  # optional sharing level of a send or accept, the end date param, and the
  # lookup of the friendship whose end date changes.
  module FriendFeatures
    extend ActiveSupport::Concern

    private

    def availability_only_enabled?
      Flipper.enabled?(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
    end

    def friend_expiry_enabled?
      Flipper.enabled?(FeatureFlags::FRIEND_EXPIRY, current_user)
    end

    # The optional visibility param of a send or accept request. Returns nil when
    # absent, the level when valid, and false when it is unknown or the flag is
    # off for the signed-in user. Then nothing is shared at a level that the user
    # did not get.
    def requested_visibility
      return nil if params[:visibility].blank?
      return false unless availability_only_enabled?

      Friendship.valid_visibility?(params[:visibility]) ? params[:visibility].to_s : false
    end

    # The form sends a date. Friendships::ExpiryTime reads it with the same rule as
    # the API: the end of that day in America/New_York. Returns nil for any
    # other value.
    def parse_expires_on
      Friendships::ExpiryTime.parse(params[:expires_on])
    end

    # The friendship or pending request with the user in params[:friend_id],
    # when the flag is on or +require_flag+ is false. Redirects when there is none.
    def find_expiry_friendship(require_flag: true)
      friend     = User.find_by_public_id(params[:friend_id])
      friendship = Friendship.unexpired.between(current_user, friend).first if friend && friend.id != current_user.id

      unless friendship && (!require_flag || friend_expiry_enabled?)
        skip_authorization
        redirect_to dashboard_friends_path, alert: "Friend not found."
        return
      end

      [ friend, friendship ]
    end
  end
end
