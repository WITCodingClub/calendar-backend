# frozen_string_literal: true

module Api
  class FriendsController < ApiController
    before_action :require_availability_only_flag, only: [ :visibility, :update_visibility, :busy_blocks ]

    def index
      authorize :friendship, :index?

      friends = current_user.friends.map do |friend|
        { id: friend.public_id, name: friend.full_name }
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

      friendship = Friendship.new(requester: current_user, addressee: friend_user)

      authorize friendship, :create?
      friendship.save!

      render json: { request_id: friendship.public_id }, status: :created
    end

    def accept
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :accept?

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

      friendship = Friendship.accepted
                             .where("(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
                                    current_user.id, friend_user.id, friend_user.id, current_user.id)
                             .first

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
        render json: { error: "You are not friends with this user" }, status: :forbidden
        return
      end

      authorize friendship, :view_schedule?

      # The friend's own setting decides. This check does not depend on the
      # flag: a level that was set while the flag was on stays in force.
      unless policy(friendship).view_full_schedule?
        render json: {
          error:      "This friend shares only availability",
          code:       "AVAILABILITY_ONLY",
          visibility: "availability_only"
        }, status: :forbidden
        return
      end

      term = find_term_by_uid
      return if performed?

      result = ProcessedEventsBuilder.new(friend_user, term).build
      render json: result, status: :ok
    end

    def is_processed
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = find_friendship_with(friend_user)

      if friendship.nil?
        render json: { error: "You are not friends with this user" }, status: :forbidden
        return
      end

      authorize friendship, :view_schedule?

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
      unless Friendship::VISIBILITIES.key?(level.to_sym)
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

    def find_accepted_friendship!
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = find_friendship_with(friend_user)
      return friendship if friendship

      render json: { error: "You are not friends with this user" }, status: :forbidden
      nil
    end

    # start_date defaults to today and end_date to six days after start_date.
    def busy_blocks_range
      from = parse_date_param(:start_date) || Time.zone.today
      return if performed?

      to = parse_date_param(:end_date) || (from + 6)
      return if performed?

      if to < from
        render json: { error: "end_date must not be before start_date" }, status: :bad_request
        return
      end

      if (to - from).to_i + 1 > BusyBlocks::MAX_DAYS
        render json: { error: "The range must be #{BusyBlocks::MAX_DAYS} days or fewer" }, status: :bad_request
        return
      end

      [ from, to ]
    end

    def parse_date_param(name)
      value = params[name]
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      render json: { error: "#{name} must be a date in YYYY-MM-DD format" }, status: :bad_request
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
      Friendship.accepted
                .where("(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
                       current_user.id, friend_user.id, friend_user.id, current_user.id)
                .first
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
