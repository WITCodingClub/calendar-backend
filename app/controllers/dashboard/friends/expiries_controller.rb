# frozen_string_literal: true

module Dashboard
  module Friends
    # The end date of the friendship or the request with one user.
    class ExpiriesController < Dashboard::ApplicationController
      include Dashboard::FriendFeatures

      # PATCH /dashboard/friends/:friend_id/expiry
      #
      # Asks for a new end date, or for a permanent friendship when the
      # "permanent" param is present. A sooner date applies at once. A later
      # date, or permanent, is a proposal that the friend must accept.
      def update
        friend, friendship = find_expiry_friendship
        return if performed?

        authorize friendship, :update_expiry?

        expires_at = params[:permanent].present? ? nil : parse_expires_on
        if params[:permanent].blank? && expires_at.nil?
          return redirect_to dashboard_friends_path, alert: "Pick a valid end date."
        end

        change = friendship.change_expiry!(to: expires_at, by: current_user)
        redirect_to dashboard_friends_path, notice: change_notice(change, friend, friendship)
      rescue ActiveRecord::RecordInvalid
        redirect_to dashboard_friends_path, alert: "Pick an end date after today."
      end

      private

      def change_notice(change, friend, friendship)
        case change
        when :shortened
          "Your friendship with #{friend.first_name} now ends on #{friendship.expires_at.to_date.to_fs(:long)}."
        when :proposed
          "You proposed a new end date. #{friend.first_name} must accept it before it applies."
        else
          "The end date did not change."
        end
      end
    end
  end
end
