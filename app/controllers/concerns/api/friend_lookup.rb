# frozen_string_literal: true

module Api
  # Friendship lookups and answers that the friends controllers share.
  module FriendLookup
    extend ActiveSupport::Concern

    EXPIRES_AT_FORMAT_ERROR = "expires_at must be a date (2026-12-01, the end of that day in America/New_York) " \
                              "or an ISO 8601 time with a UTC offset (2026-12-01T17:00:00-05:00)"

    included do
      rescue_from Friendships::OptionError, with: :render_option_error
    end

    private

    # Renders 404 and returns false when the busy times of this friend are not
    # open to the viewer yet (Friendships::Features.busy_times_readable?).
    def readable_without_flag?(friendship)
      return true if Friendships::Features.busy_times_readable?(friendship, current_user)

      render_error "Not found", status: :not_found
      false
    end

    def find_accepted_friendship!
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = Friendship.accepted_between(current_user, friend_user)
      return friendship if friendship

      render_error "You are not friends with this user", status: :forbidden, code: "NOT_FRIENDS"
      nil
    end

    def render_friend_expiry_disabled
      render_error "Temporary friendships are not enabled", status: :not_found
    end

    def render_option_error(error)
      case error.reason
      when :visibility_disabled then render_error "Not found", status: :not_found
      when :expiry_disabled     then render_friend_expiry_disabled
      when :invalid_expiry      then render_error EXPIRES_AT_FORMAT_ERROR, status: :bad_request
      when :past_expiry         then render_error "Expires at must be in the future", status: :unprocessable_content
      when :self                then render_error "Addressee cannot be yourself", status: :unprocessable_content
      else
        render_error "visibility must be one of: #{Friendship::VISIBILITIES.keys.join(", ")}",
                     status: :unprocessable_content
      end
    end
  end
end
