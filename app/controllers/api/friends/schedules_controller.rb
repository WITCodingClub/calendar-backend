# frozen_string_literal: true

module Api
  module Friends
    # What a friend's schedule shows to the user: the courses, or only the busy
    # times. The friend's visibility level decides.
    class SchedulesController < Api::BaseController
      include Api::FriendLookup
      include BusyBlocksParams
      include Api::TermLookup

      authenticate_with_token

      def processed_events
        friend_user = find_by_any_id!(User, params[:friend_id])
        friendship  = find_friendship_with(friend_user)

        if friendship.nil?
          render_not_friends
          return
        end

        authorize friendship, :view_schedule?
        return if render_availability_only_unless_full(friendship)

        term = find_term_by_uid
        return if performed?

        result = ProcessedEventsBuilder.new(friend_user, term).build
        render json: result, status: :ok
      end

      def processed
        friend_user = find_by_any_id!(User, params[:friend_id])
        friendship  = find_friendship_with(friend_user)

        if friendship.nil?
          render_not_friends
          return
        end

        authorize friendship, :view_schedule?
        # A friend who shares only availability must not learn whether the user
        # has enrollments in a term.
        return if render_availability_only_unless_full(friendship)

        term = find_term_by_uid
        return if performed?

        processed = friend_user.enrollments.exists?(term_id: term.id)
        render json: { processed: processed }, status: :ok
      end

      # GET /api/friends/:friend_id/busy_blocks?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
      #
      # The times the friend is in class, with no course data. Every accepted
      # friend can read it, whatever the friend's visibility level.
      def busy_blocks
        friendship = find_accepted_friendship!
        return if performed?

        authorize friendship, :view_availability?
        return unless readable_without_flag?(friendship)

        from, to = busy_blocks_range
        return if performed?

        friend = friendship.friend_for(current_user)
        blocks = BusyBlocks.new(friend, from: from, to: to).call
        render json: BusyBlocksSerializer.new(blocks, from: from, to: to).as_json, status: :ok
      end

      private

      # The friend's own setting decides. This check does not depend on any flag:
      # a level that was set while the flag was on stays in force. Returns true
      # when it rendered the 403.
      def render_availability_only_unless_full(friendship)
        return false if policy(friendship).view_full_schedule?

        render_error "This friend shares only availability",
                     status: :forbidden,
                     code: "AVAILABILITY_ONLY",
                     visibility: "availability_only"
        true
      end
    end
  end
end
