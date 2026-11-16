# frozen_string_literal: true

module Api
  module Friends
    # What a friend's schedule shows to the user: the courses, or only the busy
    # times. The friend's visibility level decides.
    class SchedulesController < Api::BaseController
      include Api::FriendLookup
      include Api::BusyBlocksParams
      include Api::TermLookup

      authenticate_with_token

      def processed_events
        friendship = find_accepted_friendship!
        return if performed?

        authorize friendship, :view_schedule?
        return if render_availability_only_unless_full(friendship)

        term = find_term_by_uid
        return if performed?

        result = Courses::ProcessedEventsBuilder.new(friendship.friend_for(current_user), term).build
        render json: result, status: :ok
      end

      # The most friend ids one batch request takes. A client with more
      # friends sends more than one request.
      MAX_BATCH_FRIENDS = 100

      # { "term_uid": "...", "friend_ids": ["usr_...", ...] }
      #
      # The schedules of many friends in one request (#681), in the order of
      # friend_ids. Each entry is the body that GET :friend_id/processed_events
      # gives, with friend_id added. A friend the user cannot read gives an
      # entry with error and code: NOT_FRIENDS or AVAILABILITY_ONLY.
      def processed_events_batch
        authorize :friendship, :index?

        friend_ids = batch_friend_ids
        return if performed?

        term = find_term_by_uid
        return if performed?

        friendships = requested_friendships(friend_ids)
        readable = friend_ids.filter_map { |id| friendships[id] }
                             .select { |friendship| policy(friendship).view_full_schedule? }
                             .map { |friendship| friendship.friend_for(current_user) }
        schedules = Courses::ProcessedEventsBuilder.build_for_users(readable, term)

        entries = friend_ids.map do |id|
          friendship = friendships[id]
          batch_entry(id, friendship, friendship && schedules[friendship.friend_id_for(current_user)])
        end
        render json: { term_uid: term.uid, schedules: entries }, status: :ok
      end

      def processed
        friendship = find_accepted_friendship!
        return if performed?

        authorize friendship, :view_schedule?
        # A friend who shares only availability must not learn whether the user
        # has enrollments in a term.
        return if render_availability_only_unless_full(friendship)

        term = find_term_by_uid
        return if performed?

        processed = friendship.friend_for(current_user).enrollments.exists?(term_id: term.id)
        render json: { processed: processed }, status: :ok
      end

      # The times the friend is in class, with no course data. Every accepted
      # friend can read it, whatever the friend's visibility level.
      def busy_blocks
        friendship = find_accepted_friendship!
        return if performed?

        authorize friendship, :view_availability?
        busy_times = Friendships::BusyTimes.new(current_user, friendship)
        return render_error("Not found", status: :not_found) unless busy_times.readable?

        from, to = busy_blocks_range
        return if performed?

        render json: busy_times.as_json(from, to), status: :ok
      end

      private

      # The friend_ids param, without repeats. Renders 400 and returns nil when
      # it is missing, is not a list of strings, or has too many ids.
      def batch_friend_ids
        ids = params[:friend_ids]
        unless ids.is_a?(Array) && ids.any? && ids.all? { |id| id.is_a?(String) && id.present? }
          render_error "friend_ids must be a list of friend ids", status: :bad_request
          return nil
        end

        ids = ids.uniq
        if ids.size > MAX_BATCH_FRIENDS
          render_error "friend_ids takes at most #{MAX_BATCH_FRIENDS} ids", status: :bad_request
          return nil
        end

        ids
      end

      # The accepted friendships with the users that friend_ids names, keyed by
      # the friend's public id. It loads only those rows, so the cost does not
      # grow with the user's total number of friends.
      def requested_friendships(friend_ids)
        user_ids = friend_ids.filter_map { |id| PublicIds.decode(User, id) }
        return {} if user_ids.empty?

        current_user.accepted_friendships
                    .where("friendships.requester_id IN (:ids) OR friendships.addressee_id IN (:ids)", ids: user_ids)
                    .includes(:requester, :addressee)
                    .index_by { |friendship| friendship.friend_for(current_user).public_id }
      end

      # One entry of the batch response. An unknown id gives NOT_FRIENDS, the
      # same as a user who is not a friend, so the response does not show
      # which ids exist.
      def batch_entry(friend_id, friendship, schedule)
        return { friend_id: friend_id, **schedule } if schedule

        if friendship.nil?
          { friend_id: friend_id, error: "You are not friends with this user", code: "NOT_FRIENDS" }
        else
          { friend_id: friend_id, error: "This friend shares only availability",
            code: "AVAILABILITY_ONLY", visibility: "availability_only" }
        end
      end

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
