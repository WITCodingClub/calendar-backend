# frozen_string_literal: true

class Dashboard::FriendsController < Dashboard::ApplicationController
  def index
    authorize current_user, :show?

    @friends  = current_user.friends.order(:first_name, :last_name)
    @incoming = current_user.incoming_friend_requests.includes(:requester).pending
    @outgoing = current_user.outgoing_friend_requests.includes(:addressee).pending
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

    request = FriendRequest.find_or_initialize_by(requester: current_user, addressee: addressee)

    if request.new_record? && request.save
      redirect_to dashboard_friends_path, notice: "Friend request sent to #{addressee.first_name}."
    else
      redirect_to dashboard_friends_path, alert: "Could not send request."
    end
  end

  def accept
    authorize current_user, :update?

    fr = current_user.incoming_friend_requests.find_by(id: params[:id])
    return redirect_to dashboard_friends_path, alert: "Request not found." unless fr

    fr.accept!
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
end
