# frozen_string_literal: true

module Dashboard
  # Shared by the dashboard friends controllers: the answer to a sharing level
  # or end date that Friendships::Request refuses, and the lookup of the
  # friendship whose end date changes.
  module FriendFeatures
    extend ActiveSupport::Concern

    OPTION_ALERTS = {
      self:                "You can't add yourself.",
      visibility_disabled: "Choose a valid sharing level.",
      invalid_visibility:  "Choose a valid sharing level.",
      expiry_disabled:     "Temporary friendships are not available.",
      invalid_expiry:      "Pick a valid end date.",
      past_expiry:         "Pick an end date after today."
    }.freeze

    included do
      rescue_from Friendships::OptionError do |error|
        skip_authorization
        redirect_to dashboard_friends_path, alert: OPTION_ALERTS.fetch(error.reason)
      end
    end

    private

    # The friendship or pending request with the user in params[:friend_id],
    # when the friend_expiry flag is on or +require_flag+ is false. Redirects
    # when there is none.
    def find_expiry_friendship(require_flag: true)
      friend     = User.find_by_public_id(params[:friend_id])
      friendship = Friendship.unexpired_between(current_user, friend) if friend && friend.id != current_user.id

      unless friendship && (!require_flag || Friendships::Features.expiry?(current_user))
        skip_authorization
        redirect_to dashboard_friends_path, alert: "Friend not found."
        return
      end

      [ friend, friendship ]
    end
  end
end
