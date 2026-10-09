# frozen_string_literal: true

module Dashboard
  class FriendsController < Dashboard::ApplicationController
    include ScheduleLoading
    include Dashboard::FriendFeatures

    def index
      authorize current_user, :show?

      @friendships = current_user.accepted_friendships.includes(:requester, :addressee)
                                   .sort_by { |f| friend_sort_key(f.friend_for(current_user)) }
      @friends = @friendships.map { |f| f.friend_for(current_user) }
      @friend_expiry_enabled = friend_expiry_enabled?
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
      @can_set_visibility = availability_only_enabled?

      # The friend's own setting decides what this page shows. A friend who
      # shares only availability gets busy blocks, never the course list.
      if @friendship.full_schedule_visible_to?(current_user)
        @schedule = build_schedule_for(@friend)
      else
        @week_start  = availability_week_start
        @busy_blocks = BusyBlocks.new(@friend, from: @week_start, to: @week_start + 6).call
        render :availability
      end
    end

    def create
      authorize current_user, :update?

      addressee = User.find_by_public_id(params[:friend_id])
      return redirect_to dashboard_friends_path, alert: "User not found." unless addressee

      if current_user.id == addressee.id
        return redirect_to dashboard_friends_path, alert: "You can't add yourself."
      end

      level = requested_visibility
      return redirect_to dashboard_friends_path, alert: "Choose a valid sharing level." if level == false

      friendship = Friendship.new(requester: current_user, addressee: addressee)
      friendship.requester_visibility = level if level

      if params[:expires_on].present?
        return redirect_to dashboard_friends_path, alert: "Temporary friendships are not available." unless friend_expiry_enabled?

        friendship.expires_at = parse_expires_on
        return redirect_to dashboard_friends_path, alert: "Pick a valid end date." if friendship.expires_at.nil?
        return redirect_to dashboard_friends_path, alert: "Pick an end date after today." unless friendship.expires_at.future?
      end

      # The self check above covers the only other validation, so a failure here
      # means a request or friendship already exists in one direction or the other.
      if friendship.save
        redirect_to dashboard_friends_path, notice: "Friend request sent to #{addressee.first_name}."
      else
        redirect_to dashboard_friends_path,
                    alert: "You already have a request or friendship with #{addressee.first_name}."
      end
    end

    def destroy
      authorize current_user, :update?

      friend = current_user.friends.find_by_public_id(params[:id])
      return redirect_to dashboard_friends_path, alert: "Friend not found." unless friend

      current_user.remove_friend(friend)
      redirect_to dashboard_friends_path, notice: "#{friend.first_name} removed."
    end

    private

    def availability_week_start
      Date.iso8601(params[:week_start].to_s).beginning_of_week(:monday)
    rescue Date::Error
      Time.zone.today.beginning_of_week(:monday)
    end

    # Groups show only while the friend_groups flag is on. Each list loads in a
    # fixed number of queries, however many friends and groups there are.
    def load_friend_groups
      @groups_enabled = FriendGroup.enabled_for?(current_user)
      return unless @groups_enabled

      @groups = policy_scope(FriendGroup).includes(:user, memberships: { friendship: %i[requester addressee] }).order(:name)
      @groups_by_friend = FriendGroup.by_friend_id_for(current_user)
    end

    def friend_sort_key(user)
      [ user.first_name.to_s, user.last_name.to_s ]
    end
  end
end
