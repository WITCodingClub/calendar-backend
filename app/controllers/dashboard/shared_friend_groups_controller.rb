# frozen_string_literal: true

module Dashboard
  # Sets the user's status in a friend group that a friend shared with them,
  # from the friends page: active, hidden, or opted out. Answers 404 while the
  # friend_groups flag is off for the user.
  class SharedFriendGroupsController < Dashboard::ApplicationController
    include Dashboard::FriendGroupLookup

    NOTICES = {
      "active"    => "\"%s\" shows in your groups again.",
      "hidden"    => "\"%s\" is hidden. The other members still see you.",
      "opted_out" => "You opted out of \"%s\". The other members no longer see you."
    }.freeze

    before_action :set_group

    def update
      authorize @group, :update_membership?

      status = params[:status].to_s
      return redirect_to(dashboard_friends_path, alert: "That choice is not valid.") unless NOTICES.key?(status)

      @group.membership_for(current_user).update!(status: status)
      redirect_to dashboard_friends_path, notice: format(NOTICES.fetch(status), @group.name)
    end

    private

    # Scoping to the groups shared with the user is the access check. A halted
    # before_action skips verify_authorized.
    def set_group
      @group = policy_scope(FriendGroup, policy_scope_class: FriendGroupPolicy::SharedScope)
               .find_by_public_id(params[:id])
      redirect_to dashboard_friends_path, alert: "Group not found." if @group.nil?
    end
  end
end
