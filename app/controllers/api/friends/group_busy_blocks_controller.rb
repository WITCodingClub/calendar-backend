# frozen_string_literal: true

module Api
  module Friends
    # GET /api/friends/groups/:group_id/busy_blocks?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
    #
    # The busy times of everyone in a friend group: the owner first, then each
    # member. The owner of the group can read it, and so can each member of a
    # shared group who did not opt out. A member sees the busy times of members
    # who are not the member's friends too: the owner shared the group for
    # planning. A member who opted out is left out for the other members. The
    # times hold no course data.
    #
    # The friend_groups flag gates this route. It does not use the
    # friends_availability_only gate of GET /api/friends/:friend_id/busy_blocks:
    # that gate only holds back the per-friend route during its own rollout.
    #
    # Answers 404 while the friend_groups flag is off for the user.
    class GroupBusyBlocksController < Api::BaseController
      include Api::BusyBlocksParams

      authenticate_with_token

      include Api::FriendGroupsFlag

      def index
        group = find_group
        authorize group, :view_busy_blocks?

        from, to = busy_blocks_range
        return if performed?

        blocks_by_person = BusyBlocks.for_users(group.people_for(current_user), from: from, to: to)
        render json: FriendGroupBusyBlocksSerializer.new(group, blocks_by_person, from: from, to: to).as_json,
               status: :ok
      end

      private

      # The user's own groups, then the groups shared with the user. Any other
      # group id finds nothing, so the answer is 404, not 403.
      def find_group
        group = policy_scope(FriendGroup).find_by_public_id(params[:group_id]) ||
                policy_scope(FriendGroup, policy_scope_class: FriendGroupPolicy::SharedScope)
                .find_by_public_id(params[:group_id])
        raise ActiveRecord::RecordNotFound, "Group not found" if group.nil?

        FriendGroup.includes(:user, memberships: { friendship: %i[requester addressee] }).find(group.id)
      end
    end
  end
end
