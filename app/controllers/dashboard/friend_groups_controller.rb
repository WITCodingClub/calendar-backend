# frozen_string_literal: true

module Dashboard
  # Creates, renames, and deletes friend groups from the friends page, and sets
  # their end dates. Every action answers 404 while the friend_groups flag is
  # off for the user.
  class FriendGroupsController < Dashboard::ApplicationController
    include Dashboard::FriendGroupLookup

    before_action :set_group, only: %i[update destroy]

    def create
      group = current_user.friend_groups.new
      authorize group

      save_group(group, notice: "Group \"#{params[:name].to_s.squish}\" created.")
    end

    # One Save applies the name, the end date, and the members together.
    def update
      authorize @group

      save_group(@group, notice: "Group saved.")
    end

    def destroy
      authorize @group

      @group.destroy!
      redirect_to dashboard_friends_path, notice: "Group \"#{@group.name}\" deleted."
    end

    private

    # member_ids is nil when the form sends no member list. A form that shows the
    # friend checkboxes always sends one, even if no box is checked.
    def save_group(group, notice:)
      ids = params[:member_ids].nil? ? nil : Array(params[:member_ids]).compact_blank
      attributes = params.key?(:name) ? { name: params[:name] } : {}
      if params.key?(:expires_on)
        expires_at = parse_expires_on
        return redirect_to(dashboard_friends_path, alert: "That end date is not valid.") if expires_at == false

        attributes[:expires_at] = expires_at
      end

      group.save_with_members!(attributes, friend_ids: ids)
      redirect_to dashboard_friends_path, notice: notice
    rescue FriendGroup::UnknownFriends
      redirect_to dashboard_friends_path, alert: "Some of those people are not your friends. Nothing was saved."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to dashboard_friends_path, alert: e.record.errors.full_messages.to_sentence
    end

    # The form sends a date, read with the friendship expiry rule: the end of
    # that day in America/New_York. An empty field means the group does not
    # end. Returns false for any other value.
    def parse_expires_on
      return nil if params[:expires_on].blank?

      Friendships::ExpiryTime.parse(params[:expires_on]) || false
    end

    def set_group
      @group = find_group(params[:id])
    end
  end
end
