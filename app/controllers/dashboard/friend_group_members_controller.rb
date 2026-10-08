# frozen_string_literal: true

# Adds friends to a friend group and removes them, from the friends page.
# The member id in the path is the friend's user public id.
class Dashboard::FriendGroupMembersController < Dashboard::ApplicationController
  include Dashboard::FriendGroupLookup

  before_action :set_group

  def create
    authorize @group, :manage_members?

    friendship = friendship_with(params[:friend_id])
    return redirect_to dashboard_friends_path, alert: "Friend not found." unless friendship

    @group.memberships.find_or_create_by!(friendship: friendship)
    redirect_to dashboard_friends_path, notice: "Added to \"#{@group.name}\"."
  end

  def destroy
    authorize @group, :manage_members?

    friendship = friendship_with(params[:id])
    membership = friendship && @group.memberships.find_by(friendship: friendship)
    return redirect_to dashboard_friends_path, alert: "Friend not found in this group." unless membership

    membership.destroy!
    redirect_to dashboard_friends_path, notice: "Removed from \"#{@group.name}\"."
  end

  private

  def set_group
    @group = find_group(params[:friend_group_id])
  end

  def friendship_with(friend_public_id)
    current_user.accepted_friendship_with(User.find_by_public_id(friend_public_id))
  end
end
