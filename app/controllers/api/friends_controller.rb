# frozen_string_literal: true

module Api
  class FriendsController < ApiController
    include BusyBlocksParams

    before_action :require_availability_only_flag, only: [ :update_visibility ]

    def index
      authorize :friendship, :index?

      flag_on     = Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
      friendships = Friendship.accepted_for(current_user).includes(:requester, :addressee)

      friends = friendships.map do |friendship|
        friend = friendship.friend_for(current_user)
        { id: friend.public_id, name: friend.full_name, visibility: index_visibility(friendship, flag_on) }
      end

      render json: { friends: friends }, status: :ok
    end

    def requests
      authorize :friendship, :requests?

      incoming = current_user.incoming_friend_requests.includes(:requester).map do |fr|
        {
          request_id: fr.public_id,
          from:       { id: fr.requester.public_id, name: fr.requester.full_name },
          created_at: fr.created_at.iso8601
        }
      end

      outgoing = current_user.outgoing_friend_requests.includes(:addressee).map do |fr|
        {
          request_id: fr.public_id,
          to:         { id: fr.addressee.public_id, name: fr.addressee.full_name },
          created_at: fr.created_at.iso8601
        }
      end

      render json: { incoming: incoming, outgoing: outgoing }, status: :ok
    end

    def create_request
      friend_user = resolve_friend_user
      return if performed?

      level = requested_visibility
      return if performed?

      friendship = Friendship.new(requester: current_user, addressee: friend_user)
      friendship.requester_visibility = level if level

      authorize friendship, :create?
      friendship.save!

      render json: { request_id: friendship.public_id }, status: :created
    end

    def accept
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :accept?

      level = requested_visibility
      return if performed?

      friendship.addressee_visibility = level if level
      friendship.accepted!
      friend = friendship.friend_for(current_user)

      render json: {
        friendship_id: friendship.public_id,
        friend:        { id: friend.public_id.delete_prefix("usr_"), name: friend.full_name }
      }, status: :ok
    end

    def decline
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :decline?
      friendship.destroy!
      render json: { ok: true }, status: :ok
    end

    def cancel_request
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :cancel?
      friendship.destroy!
      render json: { ok: true }, status: :ok
    end

    def unfriend
      friend_user = find_by_any_id!(User, params[:friend_id])

      friendship = Friendship.accepted_between(current_user, friend_user)

      if friendship.nil?
        render json: { error: "Friendship not found" }, status: :not_found
        return
      end

      authorize friendship, :destroy?
      friendship.destroy!
      render json: { ok: true }, status: :ok
    end

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

    def is_processed
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

    # GET /api/friends/:friend_id/visibility
    def visibility
      friendship = find_accepted_friendship!
      return if performed?

      authorize friendship, :view_schedule?
      return unless readable_without_flag?(friendship)

      render json: FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json, status: :ok
    end

    # PATCH /api/friends/:friend_id/visibility
    #
    # Sets the level for the current user's own schedule toward this friend.
    def update_visibility
      friendship = find_accepted_friendship!
      return if performed?

      authorize friendship, :update_visibility?

      level = params.require(:visibility).to_s
      unless Friendship.valid_visibility?(level)
        render json: { error: "visibility must be one of: #{Friendship::VISIBILITIES.keys.join(", ")}" },
               status: :unprocessable_content
        return
      end

      friendship.update_visibility_for!(current_user, level)
      render json: FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json, status: :ok
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

    # Answers 404 while the flag is off for the current user, so the routes
    # look absent until the privacy policy update ships.
    def require_availability_only_flag
      return if Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)

      render json: { error: "Not found" }, status: :not_found
    end

    # A read route works when the flag is on for the viewer. It also works when
    # the friend shares only availability, whatever the flag of the viewer:
    # processed_events answers 403 then, and the viewer needs this data. Else
    # it answers 404. Returns true when the read may go on.
    def readable_without_flag?(friendship)
      return true if Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
      return true unless friendship.full_schedule_visible_to?(current_user)

      render json: { error: "Not found" }, status: :not_found
      false
    end

    # Both levels of one friendship for the friends list, so the client needs
    # no visibility request for each friend. It follows readable_without_flag?:
    # nil while the viewer's flag is off and the friend shares the full schedule.
    def index_visibility(friendship, flag_on)
      return nil unless flag_on || !friendship.full_schedule_visible_to?(current_user)

      FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json.except(:friend_id)
    end

    def find_accepted_friendship!
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = find_friendship_with(friend_user)
      return friendship if friendship

      render_not_friends
      nil
    end

    def render_not_friends
      render json: { error: "You are not friends with this user", code: "NOT_FRIENDS" }, status: :forbidden
    end

    # The friend's own setting decides. This check does not depend on any flag:
    # a level that was set while the flag was on stays in force. Returns true
    # when it rendered the 403.
    def render_availability_only_unless_full(friendship)
      return false if policy(friendship).view_full_schedule?

      render json: {
        error:      "This friend shares only availability",
        code:       "AVAILABILITY_ONLY",
        visibility: "availability_only"
      }, status: :forbidden
      true
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

      render json: { error: "visibility must be one of: #{Friendship::VISIBILITIES.keys.join(", ")}" },
             status: :unprocessable_content
      nil
    end

    def resolve_friend_user
      has_id    = params[:friend_id].present?
      has_email = params[:friend_email].present?

      if has_id && has_email
        render json: { error: "Provide either friend_id or friend_email, not both" }, status: :bad_request
        return
      end

      unless has_id || has_email
        render json: { error: "friend_id or friend_email is required" }, status: :bad_request
        return
      end

      if has_email
        user = User.find_by(email: params[:friend_email].downcase.strip)
        if user.nil?
          raise ActiveRecord::RecordNotFound.new(nil, User.name)
        end
        user
      else
        find_by_any_id!(User, params[:friend_id])
      end
    end

    def find_friendship_with(friend_user)
      Friendship.accepted_between(current_user, friend_user)
    end

    def find_term_by_uid
      term_uid = params[:term_uid]

      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return nil
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return nil
      end

      term
    end
  end
end
