# frozen_string_literal: true

module Dashboard
  module Friends
    # How much of the signed-in user's own schedule one friend can see.
    class VisibilitiesController < Dashboard::ApplicationController
      require_feature FeatureFlags::FRIENDS_AVAILABILITY_ONLY, "Not found"

      def update
        friend     = current_user.friends.find_by_public_id(params[:friend_id])
        friendship = friend && Friendship.accepted_between(current_user, friend)
        unless friendship
          skip_authorization
          return redirect_to dashboard_friends_path, alert: "Friend not found."
        end

        authorize friendship, :update_visibility?
        level = params[:visibility].to_s
        unless Friendship.valid_visibility?(level)
          return redirect_to dashboard_friend_path(friend.public_id), alert: "Choose a valid sharing level."
        end

        friendship.update_visibility_for!(current_user, level)
        message = level == "full" ? "#{friend.first_name} can see your full schedule." : "#{friend.first_name} can see only when you are busy."
        redirect_to dashboard_friend_path(friend.public_id), notice: message
      end
    end
  end
end
