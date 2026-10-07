# frozen_string_literal: true

module Api
  # Named groups of friends. A group is private to its owner.
  #
  # Every action answers 404 while the friend_groups flag is off for the user.
  # Groups use public ids ("fgr_..."). Members are friends, named by their user
  # public id ("usr_..."), the same id that GET /api/friends returns.
  class FriendGroupsController < ApiController
    before_action :require_friend_groups
    before_action :set_group, except: %i[index create]

    # GET /api/friends/groups
    def index
      authorize FriendGroup

      groups = policy_scope(FriendGroup).includes(memberships: { friendship: %i[requester addressee] })
                                        .order(:name)

      render json: { groups: groups.map { |group| FriendGroupSerializer.new(group).as_json } }, status: :ok
    end

    # GET /api/friends/groups/:group_id
    def show
      authorize @group
      render_group
    end

    # POST /api/friends/groups  { "name": "Study group" }
    def create
      group = current_user.friend_groups.new(name: params.require(:name))
      authorize group
      group.save!

      render_group(group, status: :created)
    end

    # PATCH /api/friends/groups/:group_id  { "name": "Roommates" }
    def update
      authorize @group
      @group.update!(name: params.require(:name))

      render_group
    end

    # DELETE /api/friends/groups/:group_id
    def destroy
      authorize @group
      @group.destroy!

      render json: { ok: true }, status: :ok
    end

    # POST /api/friends/groups/:group_id/members  { "friend_id": "usr_..." }
    #
    # Adding a friend who is already in the group changes nothing and answers 200.
    def add_member
      authorize @group, :manage_members?

      friendship = friendship_with!(params.require(:friend_id))
      membership = @group.memberships.find_or_initialize_by(friendship: friendship)
      created    = membership.new_record?
      membership.save! if created

      render_group(status: created ? :created : :ok)
    end

    # DELETE /api/friends/groups/:group_id/members/:friend_id
    def remove_member
      authorize @group, :manage_members?

      friendship = friendship_with!(params[:friend_id])
      membership = @group.memberships.find_by(friendship: friendship)
      raise ActiveRecord::RecordNotFound, "Friend is not in this group" if membership.nil?

      membership.destroy!
      render_group
    end

    private

    def require_friend_groups
      return if FriendGroup.enabled_for?(current_user)

      render json: { error: "Friend groups are not enabled" }, status: :not_found
    end

    # Scoping to the user's own groups is the access check: another user's
    # group id finds nothing, so the answer is 404, not 403.
    def set_group
      @group = policy_scope(FriendGroup).find_by_public_id(params[:group_id])
      raise ActiveRecord::RecordNotFound, "Group not found" if @group.nil?
    end

    # A pending request or a stranger is not a friend, so both answer 404.
    def friendship_with!(friend_id)
      friendship = current_user.accepted_friendship_with(find_by_any_id(User, friend_id))
      raise ActiveRecord::RecordNotFound, "Friend not found" if friendship.nil?

      friendship
    end

    # Loads the group again with its members, so the answer shows the change.
    def render_group(group = @group, status: :ok)
      group = FriendGroup.includes(memberships: { friendship: %i[requester addressee] }).find(group.id)
      render json: { group: FriendGroupSerializer.new(group).as_json }, status: status
    end
  end
end
