# frozen_string_literal: true

module Api
  module Friends
    # Friend requests: the ones the user sent and the ones the user got.
    class RequestsController < Api::BaseController
      include Api::FriendLookup

      authenticate_with_token

      def index
        authorize :friendship, :requests?

        incoming = current_user.incoming_friend_requests.includes(:requester)
        outgoing = current_user.outgoing_friend_requests.includes(:addressee)

        render json: {
          incoming: FriendshipSerializer.render_requests(incoming, current_user),
          outgoing: FriendshipSerializer.render_requests(outgoing, current_user)
        }, status: :ok
      end

      def create
        friend_user = resolve_friend_user
        return if performed?

        friendship = Friendships::Request.build(current_user, friend_user,
                                                visibility: params[:visibility], expires_at: params[:expires_at])
        authorize friendship, :create?
        friendship.save!

        render json: { request_id: friendship.public_id, expires_at: friendship.expires_at&.iso8601 }, status: :created
      end

      def accept
        friendship = find_by_any_id!(Friendship, params[:request_id])
        authorize friendship, :accept?

        Friendships::Request.accept!(friendship, visibility: params[:visibility])
        render json: FriendshipSerializer.new(friendship, current_user).as_json, status: :ok
      end

      def decline
        friendship = find_by_any_id!(Friendship, params[:request_id])
        authorize friendship, :decline?
        friendship.destroy!
        render json: { ok: true }, status: :ok
      end

      def destroy
        friendship = find_by_any_id!(Friendship, params[:request_id])
        authorize friendship, :cancel?
        friendship.destroy!
        render json: { ok: true }, status: :ok
      end

      private

      def resolve_friend_user
        unless params[:friend_email].nil? || params[:friend_email].is_a?(String)
          render_error "friend_email must be a string", status: :bad_request
          return
        end

        has_id    = params[:friend_id].present?
        has_email = params[:friend_email].present?

        if has_id && has_email
          render_error "Provide either friend_id or friend_email, not both", status: :bad_request
          return
        end

        unless has_id || has_email
          render_error "friend_id or friend_email is required", status: :bad_request
          return
        end

        if has_email
          User.find_by(email: params[:friend_email].downcase.strip) || raise(ActiveRecord::RecordNotFound.new(nil, User.name))
        else
          find_by_any_id!(User, params[:friend_id])
        end
      end
    end
  end
end
