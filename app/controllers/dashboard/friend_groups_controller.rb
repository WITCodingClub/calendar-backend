# frozen_string_literal: true

# Creates, renames, and deletes friend groups from the friends page. Every
# action answers 404 while the friend_groups flag is off for the user.
class Dashboard::FriendGroupsController < Dashboard::ApplicationController
  include Dashboard::FriendGroupLookup

  before_action :set_group, only: %i[update destroy]

  def create
    group = current_user.friend_groups.new(name: params[:name])
    authorize group

    if group.save
      redirect_to dashboard_friends_path, notice: "Group \"#{group.name}\" created."
    else
      redirect_to dashboard_friends_path, alert: group.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @group

    if @group.update(name: params[:name])
      redirect_to dashboard_friends_path, notice: "Group renamed to \"#{@group.name}\"."
    else
      redirect_to dashboard_friends_path, alert: @group.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @group

    @group.destroy!
    redirect_to dashboard_friends_path, notice: "Group \"#{@group.name}\" deleted."
  end

  private

  def set_group
    @group = find_group(params[:id])
  end
end
