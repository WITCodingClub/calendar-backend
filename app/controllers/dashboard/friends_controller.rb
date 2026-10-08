# frozen_string_literal: true

class Dashboard::FriendsController < Dashboard::ApplicationController
  include ScheduleLoading

  def index
    authorize current_user, :show?

    @friends  = current_user.friends.order(:first_name, :last_name)
    @incoming = current_user.incoming_friend_requests.includes(:requester).pending
    @outgoing = current_user.outgoing_friend_requests.includes(:addressee).pending
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

  # PATCH /dashboard/friends/:id/visibility
  #
  # Sets how much of the current user's own schedule this friend can see.
  def visibility
    authorize current_user, :update?
    return head(:not_found) unless availability_only_enabled?

    friend = current_user.friends.find_by_public_id(params[:id])
    return redirect_to dashboard_friends_path, alert: "Friend not found." unless friend

    level = params[:visibility].to_s
    unless Friendship.valid_visibility?(level)
      return redirect_to dashboard_friend_path(friend.public_id), alert: "Choose a valid sharing level."
    end

    Friendship.accepted_between(current_user, friend).update_visibility_for!(current_user, level)
    message = level == "full" ? "#{friend.first_name} can see your full schedule." : "#{friend.first_name} can see only when you are busy."
    redirect_to dashboard_friend_path(friend.public_id), notice: message
  end

  def requests
    authorize current_user, :show?

    @incoming = current_user.incoming_friend_requests.includes(:requester).pending
    @outgoing = current_user.outgoing_friend_requests.includes(:addressee).pending
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

    # The self check above covers the only other validation, so a failure here
    # means a request or friendship already exists in one direction or the other.
    if friendship.save
      redirect_to dashboard_friends_path, notice: "Friend request sent to #{addressee.first_name}."
    else
      redirect_to dashboard_friends_path,
                  alert: "You already have a request or friendship with #{addressee.first_name}."
    end
  end

  def accept
    authorize current_user, :update?

    fr = current_user.incoming_friend_requests.find_by(id: params[:id])
    return redirect_to dashboard_friends_path, alert: "Request not found." unless fr

    level = requested_visibility
    return redirect_to dashboard_friends_path, alert: "Choose a valid sharing level." if level == false

    fr.addressee_visibility = level if level
    fr.accepted!
    redirect_to dashboard_friends_path, notice: "#{fr.requester.first_name} added as a friend."
  end

  def decline
    authorize current_user, :update?

    fr = current_user.incoming_friend_requests.find_by(id: params[:id])
    return redirect_to dashboard_friends_path, alert: "Request not found." unless fr

    fr.destroy!
    redirect_to dashboard_friends_path, notice: "Request declined."
  end

  def destroy
    authorize current_user, :update?

    friend = current_user.friends.find_by_public_id(params[:id])
    return redirect_to dashboard_friends_path, alert: "Friend not found." unless friend

    current_user.remove_friend(friend)
    redirect_to dashboard_friends_path, notice: "#{friend.first_name} removed."
  end

  private

  # The optional visibility param of a send or accept request. Returns nil when
  # absent, the level when valid, and false when it is unknown or the flag is
  # off for the signed-in user. Then nothing is shared at a level that the user
  # did not get.
  def requested_visibility
    return nil if params[:visibility].blank?
    return false unless availability_only_enabled?

    Friendship.valid_visibility?(params[:visibility]) ? params[:visibility].to_s : false
  end

  def availability_only_enabled?
    Flipper.enabled?(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
  end

  def availability_week_start
    Date.iso8601(params[:week_start].to_s).beginning_of_week(:monday)
  rescue Date::Error
    Time.zone.today.beginning_of_week(:monday)
  end
end
