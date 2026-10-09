# frozen_string_literal: true

module Dashboard
  module Friends
    # The signed-in user's pending friend requests. update accepts an incoming
    # request and destroy declines it. Dashboard::FriendsController#create
    # sends a request.
    class RequestsController < Dashboard::ApplicationController
      include Dashboard::FriendFeatures

      # FriendshipMailer links to the requests page. A user with no processed
      # courses must be able to answer a request from that email (#644), so the
      # requests page and its actions skip the onboarding gate. The friends list
      # and a friend's schedule stay gated.
      skip_before_action :require_processed_courses

      def index
        authorize current_user, :show?

        @friend_expiry_enabled = friend_expiry_enabled?
        @incoming = current_user.incoming_friend_requests.includes(:requester).pending
        @outgoing = current_user.outgoing_friend_requests.includes(:addressee).pending
      end

      # PATCH /dashboard/friends/requests/:id
      #
      # Accepts the incoming request, with the optional sharing level.
      def update
        authorize current_user, :update?

        fr = current_user.incoming_friend_requests.find_by(id: params[:id])
        return redirect_to friend_requests_return_path, alert: "Request not found." unless fr

        level = requested_visibility
        return redirect_to dashboard_friends_path, alert: "Choose a valid sharing level." if level == false

        fr.addressee_visibility = level if level
        fr.accepted!
        redirect_to friend_requests_return_path, notice: "#{fr.requester.first_name} added as a friend."
      end

      # DELETE /dashboard/friends/requests/:id
      #
      # Declines the incoming request.
      def destroy
        authorize current_user, :update?

        fr = current_user.incoming_friend_requests.find_by(id: params[:id])
        return redirect_to friend_requests_return_path, alert: "Request not found." unless fr

        fr.destroy!
        redirect_to friend_requests_return_path, notice: "Request declined."
      end
    end
  end
end
