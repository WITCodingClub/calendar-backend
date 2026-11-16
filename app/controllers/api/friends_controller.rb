# frozen_string_literal: true

module Api
  class FriendsController < BaseController
    include Api::FriendLookup

    authenticate_with_token

    def index
      authorize :friendship, :index?

      flag_on     = Friendships::Features.availability_only?(current_user)
      friendships = current_user.accepted_friendships.includes(:requester, :addressee)
      # Each friend gets a "groups" key only while the friend groups flag is on.
      # The groups for the whole list load in one pass, not one query per friend.
      groups_by_friend = FriendGroup.by_friend_id_for(current_user) if Friendships::Features.groups?(current_user)

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

    # Asks for a new end date on the friendship or the pending request with
    # this user. Send "expires_at": null for a permanent friendship. A sooner
    # date applies at once. A later date, or null, becomes a proposal that the
    # other user must accept. "expiry_change" in the response says which.
    #
    # The API cannot accept, decline, or withdraw a proposal (#719). The other
    # user gets an email and answers on the web dashboard.
    def update_expiry
      return render_friend_expiry_disabled unless Friendships::Features.expiry?(current_user)

      friendship = find_unexpired_friendship_or_request
      return if performed?

      authorize friendship, :update_expiry?

      unless params.key?(:expires_at)
        render_error "expires_at is required. Send null to make the friendship permanent.", status: :bad_request
        return
      end

      expires_at = params[:expires_at].nil? ? nil : Friendships::Request.expiry_for(current_user, params[:expires_at])

      change = friendship.change_expiry!(to: expires_at, by: current_user)
      render json: FriendshipSerializer.new(friendship, current_user).as_json.merge(expiry_change: change.to_s),
             status: :ok
    end

    def destroy
      removal = Friendships::Removal.new(current_user, find_by_any_id!(User, params[:friend_id]))
      return render_error("Friendship not found", status: :not_found) unless removal.found?

      authorize removal.friendship, :destroy?
      removal.call
      render json: { ok: true }, status: :ok
    end

    private

    # Both levels of one friendship for the friends list, so the client needs
    # no visibility request for each friend. Nil while the levels are not open
    # to the viewer (Friendships::Features.busy_times_readable?).
    def index_visibility(friendship, flag_on)
      return nil unless Friendships::Features.busy_times_readable?(friendship, current_user, flag_on: flag_on)

      FriendshipVisibilitySerializer.new(friendship, viewer: current_user).as_json.except(:friend_id)
    end

    def find_unexpired_friendship_or_request
      friend_user = find_by_any_id!(User, params[:friend_id])
      friendship  = Friendship.unexpired_between(current_user, friend_user)
      return friendship if friendship

      render_error "Friendship not found", status: :not_found
      nil
    end
  end
end
