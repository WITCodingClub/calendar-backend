# frozen_string_literal: true

module Api
  # Friendship lookups and checks that the friends controllers share.
  module FriendLookup
    extend ActiveSupport::Concern

    EXPIRES_AT_FORMAT_ERROR = "expires_at must be a date (2026-12-01, the end of that day in America/New_York) " \
                              "or an ISO 8601 time with a UTC offset (2026-12-01T17:00:00-05:00)"

    private

    # Answers 404 while the flag is off for the current user, so the routes
    # look absent until the privacy policy update ships.
    def require_availability_only_flag
      return if Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)

      render_error "Not found", status: :not_found
    end

    # A read route works when the flag is on for the viewer. It also works when
    # the friend shares only availability, whatever the flag of the viewer:
    # processed_events answers 403 then, and the viewer needs this data. Else
    # it answers 404. Returns true when the read may go on.
    def readable_without_flag?(friendship)
      return true if Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
      return true unless friendship.full_schedule_visible_to?(current_user)

      render_error "Not found", status: :not_found
      false
    end

    def find_accepted_friendship!
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = find_friendship_with(friend_user)
      return friendship if friendship

      render_not_friends
      nil
    end

    def render_not_friends
      render_error "You are not friends with this user", status: :forbidden, code: "NOT_FRIENDS"
    end

    # Reads the optional visibility param of a send or accept request. Returns
    # the level, or nil when the param is absent. Renders an error and returns
    # nil when the actor's flag is off (404) or the level is unknown (422).
    def requested_visibility
      return nil if params[:visibility].blank?

      require_availability_only_flag
      return nil if performed?

      level = params[:visibility].to_s
      return level if Friendship.valid_visibility?(level)

      render_error "visibility must be one of: #{Friendship::VISIBILITIES.keys.join(", ")}",
                   status: :unprocessable_content
      nil
    end

    def find_friendship_with(friend_user)
      Friendship.accepted_between(current_user, friend_user)
    end

    def friend_expiry_enabled?
      Flipper.enabled?(FlipperFlags::FRIEND_EXPIRY, current_user)
    end

    def render_friend_expiry_disabled
      render_error "Temporary friendships are not enabled", status: :not_found
    end

    # Reads params[:expires_at] with FriendshipExpiryTime, the rule the
    # dashboard also uses. Renders 400 and returns nil for any other value.
    def parse_expires_at
      expires_at = FriendshipExpiryTime.parse(params[:expires_at])
      return expires_at if expires_at

      render_error EXPIRES_AT_FORMAT_ERROR, status: :bad_request
      nil
    end
  end
end
