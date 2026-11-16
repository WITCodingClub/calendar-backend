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

        @friend_expiry_enabled = Friendships::Features.expiry?(current_user)
        @incoming = current_user.incoming_friend_requests.includes(:requester).pending
        @outgoing = current_user.outgoing_friend_requests.includes(:addressee).pending
      end

      # Accepts the incoming request, with the optional sharing level.
      def update
        request = find_incoming_request
        return unless request

        authorize request, :accept?
        Friendships::Request.accept!(request, visibility: params[:visibility])
        redirect_to friend_requests_return_path, notice: "#{request.requester.first_name} added as a friend."
      end

      # Declines the incoming request.
      def destroy
        request = find_incoming_request
        return unless request

        authorize request, :decline?
        request.destroy!
        redirect_to friend_requests_return_path, notice: "Request declined."
      end

      private

      def find_incoming_request
        request = current_user.incoming_friend_requests.find_by(id: params[:id])
        return request if request

        skip_authorization
        redirect_to friend_requests_return_path, alert: "Request not found."
        nil
      end
    end
  end
end
