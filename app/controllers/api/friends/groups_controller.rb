# frozen_string_literal: true

module Api
  module Friends
    # Named groups of friends that the user owns. A group is private to its
    # owner until the owner sets "shared": true. Then its members see it, read
    # only, through SharedGroupsController. docs/friend-groups.md has the API.
    #
    # Every action answers 404 while the friend_groups flag is off for the user.
    # Groups use public ids ("fgr_..."). Members are friends, named by their user
    # public id ("usr_..."), the same id that GET /api/friends returns.
    #
    # A group can have an end date, "expires_at". It uses the friendship expiry
    # rule (Friendships::ExpiryTime): a date means the end of that day in
    # America/New_York. When it passes, the group is removed. The friendships
    # stay. null means the group does not end.
    #
    # "color" is a "#rrggbb" hex string or null. "shared" is true or false.
    class GroupsController < Api::BaseController
      # An update must change at least one of these.
      UPDATE_KEYS = %i[name member_ids expires_at shared color].freeze

      authenticate_with_token

      include Api::FriendGroupsFlag

      before_action :set_group, except: %i[index create]

      rescue_from FriendGroup::UnknownFriends, with: :render_unknown_friends

      # GET /api/friends/groups
      def index
        authorize FriendGroup

        groups = policy_scope(FriendGroup).includes(:user, memberships: { friendship: %i[requester addressee] })
                                          .order(:name)

        render json: { groups: groups.map { |group| FriendGroupSerializer.new(group).as_json } }, status: :ok
      end

      # GET /api/friends/groups/:group_id
      def show
        authorize @group
        render_group
      end

      # POST /api/friends/groups
      #   { "name": "Study group", "member_ids": ["usr_..."], "expires_at": "2026-12-01",
      #     "shared": true, "color": "#33b679" }
      #
      # Only name is required. The group and its members save in
      # one transaction.
      def create
        group = current_user.friend_groups.new
        authorize group
        group.save_with_members!(group_attributes.merge(name: params.require(:name)), friend_ids: member_ids)

        render_group(group, status: :created)
      end

      # PATCH /api/friends/groups/:group_id
      #   { "name": "Roommates", "member_ids": ["usr_..."], "expires_at": null,
      #     "shared": false, "color": null }
      #
      # Each key is optional, but one must be there.
      # When member_ids is there, it REPLACES the members. If any id is not an
      # accepted friend, the answer is 422 and nothing changes.
      def update
        authorize @group
        raise ActionController::ParameterMissing, :name unless UPDATE_KEYS.any? { |key| params.key?(key) }

        @group.save_with_members!(group_attributes, friend_ids: member_ids)

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

      # The name, end date, shared flag, and color, for each key the request
      # has. An end date that does not follow the expiry rule, or a shared value
      # that is not true or false, is a bad request. A date in the past, or a
      # color that is not "#rrggbb", fails validation and answers 422.
      def group_attributes
        attributes = params.key?(:name) ? { name: params[:name] } : {}
        attributes[:expires_at] = parse_group_expires_at if params.key?(:expires_at)
        attributes[:shared] = parse_shared if params.key?(:shared)
        attributes[:color] = params[:color] if params.key?(:color)
        attributes
      end

      def parse_shared
        return params[:shared] if [ true, false ].include?(params[:shared])

        raise ActionController::BadRequest, "shared must be true or false"
      end

      def parse_group_expires_at
        return nil if params[:expires_at].nil?

        Friendships::ExpiryTime.parse(params[:expires_at]) ||
          raise(ActionController::BadRequest, Api::FriendLookup::EXPIRES_AT_FORMAT_ERROR)
      end

      # nil when the request has no member_ids. Anything but a list of strings is a
      # bad request.
      def member_ids
        return nil unless params.key?(:member_ids)

        ids = params[:member_ids]
        unless ids.is_a?(Array) && ids.all?(String)
          raise ActionController::BadRequest, "member_ids must be a list of friend ids"
        end

        ids
      end

      def render_unknown_friends(error)
        render_error "Friend not found: #{error.ids.join(', ')}",
                     status: :unprocessable_content,
                     invalid_member_ids: error.ids
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
        group = FriendGroup.includes(:user, memberships: { friendship: %i[requester addressee] }).find(group.id)
        render json: { group: FriendGroupSerializer.new(group).as_json }, status: status
      end
    end
  end
end
