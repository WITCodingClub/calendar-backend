# frozen_string_literal: true

module Dashboard
  class FriendsController < Dashboard::ApplicationController
    include Dashboard::FriendFeatures

    def index
      authorize current_user, :show?

      @friendships = current_user.accepted_friendships.includes(:requester, :addressee)
                                   .sort_by { |f| f.friend_for(current_user).then { |u| [ u.first_name.to_s, u.last_name.to_s ] } }
      @friends = @friendships.map { |f| f.friend_for(current_user) }
      @friend_expiry_enabled = Friendships::Features.expiry?(current_user)
      @incoming = current_user.incoming_friend_requests.includes(:requester).pending
      @outgoing = current_user.outgoing_friend_requests.includes(:addressee).pending

      load_friend_groups
    end

    def show
      authorize current_user, :show?

      # Scoping to accepted friends is the access check: a pending request or a
      # stranger's id finds nothing.
      @friend = current_user.friends.find_by_public_id(params[:id])
      return redirect_to dashboard_friends_path, alert: "Friend not found." unless @friend

      @friendship = Friendship.accepted_between(current_user, @friend)
      @can_set_visibility = Friendships::Features.availability_only?(current_user)

      # The friend's own setting decides what this page shows. A friend who
      # shares only availability gets busy blocks, never the course list.
      if @friendship.full_schedule_visible_to?(current_user)
        @schedule = Courses::Schedule.build(@friend, **schedule_params)
      else
        @week_start  = Courses::Schedule.week_start_for(params[:week_start])
        @busy_blocks = Friendships::BusyTimes.new(current_user, @friendship).blocks(@week_start, @week_start + 6)
        render :availability
      end
    end

    def create
      addressee = User.find_by_public_id(params[:friend_id])
      unless addressee
        skip_authorization
        return redirect_to dashboard_friends_path, alert: "User not found."
      end

      friendship = Friendships::Request.build(current_user, addressee,
                                              visibility: params[:visibility], expires_at: params[:expires_on])
      authorize friendship, :create?

      # Friendships::Request checks every other value, so a failure here means a
      # request or friendship already exists in one direction or the other.
      if friendship.save
        redirect_to dashboard_friends_path, notice: "Friend request sent to #{addressee.first_name}."
      else
        redirect_to dashboard_friends_path,
                    alert: "You already have a request or friendship with #{addressee.first_name}."
      end
    end

    def destroy
      friend  = User.find_by_public_id(params[:id])
      removal = Friendships::Removal.new(current_user, friend)
      unless removal.found?
        skip_authorization
        return redirect_to dashboard_friends_path, alert: "Friend not found."
      end

      authorize removal.friendship, :destroy?
      removal.call
      redirect_to dashboard_friends_path, notice: "#{friend.first_name} removed."
    end

    private

    # Groups show only while the friend_groups flag is on. Each list loads in a
    # fixed number of queries, however many friends and groups there are.
    def load_friend_groups
      @groups_enabled = Friendships::Features.groups?(current_user)
      return unless @groups_enabled

      @groups = policy_scope(FriendGroup).with_members.order(:name)
      @shared_groups = policy_scope(FriendGroup, policy_scope_class: FriendGroupPolicy::SharedScope)
                       .with_members.order(:name, :id)
      @groups_by_friend = FriendGroup.by_friend_id_for(current_user)
    end
  end
end
