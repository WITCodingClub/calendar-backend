# frozen_string_literal: true

module Api
  module Friends
    # The visibility level of each side of a friendship.
    class VisibilitiesController < Api::BaseController
      include Api::FriendLookup

      authenticate_with_token

      before_action :require_availability_only_flag, only: [ :update ]

      # GET /api/friends/:friend_id/visibility
      def show
        friendship = find_accepted_friendship!
        return if performed?

        authorize friendship, :view_schedule?
        return unless readable_without_flag?(friendship)

        render json: FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json, status: :ok
      end

      # PATCH /api/friends/:friend_id/visibility
      #
      # Sets the level for the current user's own schedule toward this friend.
      def update
        friendship = find_accepted_friendship!
        return if performed?

        authorize friendship, :update_visibility?

        level = params.require(:visibility).to_s
        unless Friendship.valid_visibility?(level)
          render_error "visibility must be one of: #{Friendship::VISIBILITIES.keys.join(", ")}",
                       status: :unprocessable_content
          return
        end

        friendship.update_visibility_for!(current_user, level)
        render json: FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json, status: :ok
      end
    end
  end
end
