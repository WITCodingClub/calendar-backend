# frozen_string_literal: true

module Api
  class FriendsController < BaseController
    include Api::FriendLookup

    authenticate_with_token

    def index
      authorize :friendship, :index?

      flag_on     = Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
      friendships = current_user.accepted_friendships.includes(:requester, :addressee)
      # Each friend gets a "groups" key only while the friend groups flag is on.
      # The groups for the whole list load in one pass, not one query per friend.
      groups_by_friend = FriendGroup.by_friend_id_for(current_user) if FriendGroup.enabled_for?(current_user)

      friends = friendships.map do |friendship|
        friend = friendship.friend_for(current_user)
        FriendSerializer.new(
          friend,
          visibility: index_visibility(friendship, flag_on),
          groups: groups_by_friend && groups_by_friend[friend.id]
        ).as_json.merge(FriendshipSerializer.new(friendship, current_user).expiry_json)
      end

      render json: { friends: friends }, status: :ok
    end

    # PATCH /api/friends/:friend_id/expiry
    #
    # Asks for a new end date on the friendship or the pending request with
    # this user. Send "expires_at": null for a permanent friendship. A sooner
    # date applies at once. A later date, or null, becomes a proposal that the
    # other user must accept. "expiry_change" in the response says which.
    #
    # The API cannot accept, decline, or withdraw a proposal (#719). The other
    # user gets an email and answers on the web dashboard.
    def update_expiry
      return render_friend_expiry_disabled unless friend_expiry_enabled?

      friendship = find_unexpired_friendship_or_request
      return if performed?

      authorize friendship, :update_expiry?

      unless params.key?(:expires_at)
        render_error "expires_at is required. Send null to make the friendship permanent.", status: :bad_request
        return
      end

      expires_at = params[:expires_at].nil? ? nil : parse_expires_at
      return if performed?

      change = friendship.change_expiry!(to: expires_at, by: current_user)
      render json: FriendshipSerializer.new(friendship, current_user).as_json.merge(expiry_change: change.to_s),
             status: :ok
    end

    def destroy
      friend_user = find_by_any_id!(User, params[:friend_id])

      friendship = Friendship.accepted_between(current_user, friend_user)

      if friendship.nil?
        render_error "Friendship not found", status: :not_found
        return
      end

      authorize friendship, :destroy?
      friendship.destroy!
      render json: { ok: true }, status: :ok
    end

    private

    # Both levels of one friendship for the friends list, so the client needs
    # no visibility request for each friend. It follows readable_without_flag?:
    # nil while the viewer's flag is off and the friend shares the full schedule.
    def index_visibility(friendship, flag_on)
      return nil unless flag_on || !friendship.full_schedule_visible_to?(current_user)

      FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json.except(:friend_id)
    end

    def find_unexpired_friendship_or_request
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = Friendship.unexpired.between(current_user, friend_user).first
      return friendship if friendship

      render_error "Friendship not found", status: :not_found
      nil
    end
  end
end
