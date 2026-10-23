# frozen_string_literal: true

module Api
  module Friends
    # Friend groups that other users shared with the user (extension#213). The
    # user is a member: a friend of the owner whom the owner put in the group.
    # These groups are read only. The user sets their own status in each one
    # (FriendGroupMembership#status): active, hidden, or opted_out.
    #
    # Every action answers 404 while the friend_groups flag is off for the user.
    class SharedGroupsController < Api::BaseController
      authenticate_with_token

      include Api::FriendGroupsFlag

      before_action :set_group, except: :index

      # GET /api/friends/shared_groups
      # GET /api/friends/shared_groups?include_hidden=true
      #
      # Lists the active groups. include_hidden=true adds the hidden groups and
      # the groups the user opted out of, so the user can change them back.
      def index
        authorize FriendGroup

        groups = shared_groups.includes(:user, memberships: { friendship: %i[requester addressee] })
                              .order(:name, :id).to_a
        groups.select! { |group| group.membership_for(current_user).active? } unless include_hidden?

        render json: { groups: groups.map { |group| serialize(group) } }, status: :ok
      end

      # GET /api/friends/shared_groups/:group_id
      def show
        authorize @group, :show_shared?

        render_group
      end

      # PATCH /api/friends/shared_groups/:group_id  { "status": "hidden" }
      #
      # status is "active", "hidden", or "opted_out". Any other value answers 422.
      def update
        authorize @group, :update_membership?

        status = params.require(:status)
        raise ActionController::BadRequest, "status must be a string" unless status.is_a?(String)

        @group.membership_for(current_user).update!(status: status)
        render_group
      end

      private

      def shared_groups
        policy_scope(FriendGroup, policy_scope_class: FriendGroupPolicy::SharedScope)
      end

      def include_hidden?
        ActiveModel::Type::Boolean.new.cast(params[:include_hidden]) || false
      end

      def serialize(group)
        SharedFriendGroupSerializer.new(group, viewer: current_user).as_json
      end

      # Loads the group again with its members, so the answer shows the change.
      def render_group
        group = FriendGroup.includes(:user, memberships: { friendship: %i[requester addressee] }).find(@group.id)
        render json: { group: serialize(group) }, status: :ok
      end

      # Scoping to the groups shared with the user is the access check: any
      # other group id finds nothing, so the answer is 404, not 403.
      def set_group
        @group = shared_groups.find_by_public_id(params[:group_id])
        raise ActiveRecord::RecordNotFound, "Group not found" if @group.nil?
      end
    end
  end
end
