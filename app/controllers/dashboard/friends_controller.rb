# frozen_string_literal: true

class Dashboard::FriendsController < Dashboard::ApplicationController
  include ScheduleLoading

  # FriendshipMailer links to the requests page. A user with no processed
  # courses must be able to answer a request from that email (#644), so the
  # requests page and its actions skip the onboarding gate. The friends list
  # and a friend's schedule stay gated.
  skip_before_action :require_processed_courses, only: %i[requests accept decline]

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

    @friend_expiry_enabled = friend_expiry_enabled?
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

  def accept
    authorize current_user, :update?

    fr = current_user.incoming_friend_requests.find_by(id: params[:id])
    return redirect_to friend_requests_return_path, alert: "Request not found." unless fr

    level = requested_visibility
    return redirect_to dashboard_friends_path, alert: "Choose a valid sharing level." if level == false

    fr.addressee_visibility = level if level
    fr.accepted!
    redirect_to friend_requests_return_path, notice: "#{fr.requester.first_name} added as a friend."
  end

  def decline
    authorize current_user, :update?

    fr = current_user.incoming_friend_requests.find_by(id: params[:id])
    return redirect_to friend_requests_return_path, alert: "Request not found." unless fr

    fr.destroy!
    redirect_to friend_requests_return_path, notice: "Request declined."
  end

  # PATCH /dashboard/friends/:id/expiry
  #
  # Asks for a new end date on the friendship or the request with this user,
  # or for a permanent friendship when the "permanent" param is present. A
  # sooner date applies at once. A later date, or permanent, is a proposal that
  # the friend must accept.
  def expiry
    friend, friendship = find_expiry_friendship
    return if performed?

    authorize friendship, :update_expiry?

    expires_at = params[:permanent].present? ? nil : parse_expires_on
    if params[:permanent].blank? && expires_at.nil?
      return redirect_to dashboard_friends_path, alert: "Pick a valid end date."
    end

    change = friendship.change_expiry!(to: expires_at, by: current_user)
    redirect_to dashboard_friends_path, notice: expiry_change_notice(change, friend, friendship)
  rescue ActiveRecord::RecordInvalid
    redirect_to dashboard_friends_path, alert: "Pick an end date after today."
  end

  # POST /dashboard/friends/:id/accept_expiry
  #
  # Works with the flag off. The proposal email links here, and the proposer
  # already had the flag.
  def accept_expiry
    friend, friendship = find_expiry_friendship(require_flag: false)
    return if performed?

    authorize friendship, :accept_expiry?
    friendship.accept_expiry_proposal!(by: current_user)

    notice = if friendship.temporary?
      "Your friendship with #{friend.first_name} now ends on #{friendship.expires_at.to_date.to_fs(:long)}."
    else
      "#{friend.first_name} is now a permanent friend."
    end
    redirect_to dashboard_friends_path, notice: notice
  end

  # POST /dashboard/friends/:id/decline_expiry
  #
  # Declines the friend's proposal, or withdraws your own. Works with the
  # flag off, the same as accept_expiry.
  def decline_expiry
    _friend, friendship = find_expiry_friendship(require_flag: false)
    return if performed?

    authorize friendship, :decline_expiry?
    friendship.decline_expiry_proposal!(by: current_user)

    redirect_to dashboard_friends_path, notice: "The proposal is closed. The end date did not change."
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
    Flipper.enabled?(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
  end

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

  def friend_expiry_enabled?
    Flipper.enabled?(FeatureFlags::FRIEND_EXPIRY, current_user)
  end

  # The form sends a date. FriendshipExpiryTime reads it with the same rule as
  # the API: the end of that day in America/New_York. Returns nil for any
  # other value.
  def parse_expires_on
    FriendshipExpiryTime.parse(params[:expires_on])
  end

  # The friendship or pending request with the user in params[:id], when the
  # flag is on or +require_flag+ is false. Redirects when there is none.
  def find_expiry_friendship(require_flag: true)
    friend     = User.find_by_public_id(params[:id])
    friendship = Friendship.unexpired.between(current_user, friend).first if friend && friend.id != current_user.id

    unless friendship && (!require_flag || friend_expiry_enabled?)
      skip_authorization
      redirect_to dashboard_friends_path, alert: "Friend not found."
      return
    end

    [ friend, friendship ]
  end

  def expiry_change_notice(change, friend, friendship)
    case change
    when :shortened
      "Your friendship with #{friend.first_name} now ends on #{friendship.expires_at.to_date.to_fs(:long)}."
    when :proposed
      "You proposed a new end date. #{friend.first_name} must accept it before it applies."
    else
      "The end date did not change."
    end
  end

  def friend_sort_key(user)
    [ user.first_name.to_s, user.last_name.to_s ]
  end
end
