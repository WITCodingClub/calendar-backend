# frozen_string_literal: true

module Api
  class FriendsController < ApiController
    # GET /api/friends
    # Returns accepted friends: { friends: [{ id: string, name: string }] }
    def index
      authorize :friendship, :index?

      friends = current_user.friends.map do |friend|
        {
          id: friend.public_id,
          name: friend.full_name
        }
      end

      render json: { friends: friends }, status: :ok
    end

    # GET /api/friends/requests
    # Returns { incoming: [...], outgoing: [...] }
    def requests
      authorize :friendship, :requests?

      incoming = current_user.incoming_friend_requests.includes(:requester).map do |fr|
        {
          request_id: fr.public_id,
          from: {
            id: fr.requester.public_id,
            name: fr.requester.full_name
          },
          created_at: fr.created_at.iso8601
        }
      end

      outgoing = current_user.outgoing_friend_requests.includes(:addressee).map do |fr|
        {
          request_id: fr.public_id,
          to: {
            id: fr.addressee.public_id,
            name: fr.addressee.full_name
          },
          created_at: fr.created_at.iso8601
        }
      end

      render json: { incoming: incoming, outgoing: outgoing }, status: :ok
    end

    # POST /api/friends/requests
    # Create request with { friend_id: string }
    def create_request
      friend_user = find_by_any_id!(User, params[:friend_id])

      friendship = Friendship.new(
        requester: current_user,
        addressee: friend_user
      )

      authorize friendship, :create?

      friendship.save!

      render json: { request_id: friendship.public_id }, status: :created
    end

    # POST /api/friends/requests/:request_id/accept
    def accept
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :accept?

      friendship.accepted!

      friend = friendship.friend_for(current_user)

      render json: {
        friendship_id: friendship.public_id,
        friend: {
          id: friend.public_id,
          name: friend.full_name
        }
      }, status: :ok
    end

    # POST /api/friends/requests/:request_id/decline
    def decline
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :decline?

      friendship.destroy!

      render json: { ok: true }, status: :ok
    end

    # DELETE /api/friends/requests/:request_id
    # Cancel outgoing request
    def cancel_request
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :cancel?

      friendship.destroy!

      render json: { ok: true }, status: :ok
    end

    # DELETE /api/friends/:friend_id
    # Unfriend
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

    # POST /api/friends/:friend_id/processed_events
    # Get friend's schedule (same format as /user/processed_events)
    def processed_events
      friend_user = find_by_any_id!(User, params[:friend_id])

      # Find the accepted friendship
      friendship = find_friendship_with(friend_user)

      if friendship.nil?
        render json: { error: "You are not friends with this user" }, status: :forbidden
        return
      end

      authorize friendship, :view_schedule?

      term = find_term_by_uid
      return if performed?

      result = ProcessedEventsBuilder.new(friend_user, term).build

      render json: result, status: :ok
    end

    # POST /api/friends/:friend_id/is_processed
    # Check if friend has courses for term
    def is_processed
      friend_user = find_by_any_id!(User, params[:friend_id])

      # Find the accepted friendship
      friendship = find_friendship_with(friend_user)

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

    private

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
