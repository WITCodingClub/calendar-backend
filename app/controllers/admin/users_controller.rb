# frozen_string_literal: true

module Admin
  class UsersController < Admin::ApplicationController
    before_action :set_user, only: [
      :show, :edit, :update, :destroy,
      :revoke_oauth_credential, :refresh_oauth_credential,
      :force_calendar_sync, :add_friend, :remove_friend
    ]

    def index
      @users = policy_scope(User).order(created_at: :desc)

      if params[:search].present?
        search_term = params[:search].strip

        if search_term.match?(/^\d+$/)
          @users = @users.where(id: search_term.to_i)
        else
          name_search = "%#{search_term}%"
          @users = @users.where(
            "users.email ILIKE ? OR CONCAT(users.first_name, users.last_name) ILIKE ? OR CONCAT(users.first_name, ' ', users.last_name) ILIKE ?",
            name_search, name_search, name_search
          )
        end
      end

      @users = @users.page(params[:page]).per(25)
    end

    def show
      authorize @user

      @enrollments_by_term = @user.enrollments
                                  .includes({ course: :faculties }, :term)
                                  .joins(:term)
                                  .order("terms.year DESC, terms.season DESC")
                                  .group_by(&:term)

      @oauth_credentials = @user.oauth_credentials
                                .includes(:google_calendar)
                                .order(created_at: :desc)
    end

    def edit
      authorize @user
    end

    def update
      authorize @user

      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User was successfully updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @user
      @user.destroy
      redirect_to admin_users_path, notice: "User was successfully deleted."
    end

    def revoke_oauth_credential
      authorize @user, :revoke_oauth_credential?
      credential = @user.oauth_credentials.find(params[:credential_id])

      RevokeOauthCredentialJob.perform_later(credential.id)
      redirect_to admin_user_path(@user), notice: "OAuth credential for #{credential.email} is being revoked."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_user_path(@user), alert: "OAuth credential not found."
    end

    def refresh_oauth_credential
      authorize @user, :refresh_oauth_credential?
      credential = @user.oauth_credentials.find(params[:credential_id])

      if credential.refresh_token.blank?
        redirect_to admin_user_path(@user), alert: "No refresh token available for #{credential.email}. User needs to re-authenticate."
        return
      end

      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id:     Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        refresh_token: credential.refresh_token,
        scope:         ["https://www.googleapis.com/auth/calendar"]
      )
      credentials.refresh!

      credential.update!(
        access_token:     credentials.access_token,
        token_expires_at: Time.current + credentials.expires_in.seconds
      )

      redirect_to admin_user_path(@user), notice: "OAuth token refreshed for #{credential.email}."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_user_path(@user), alert: "OAuth credential not found."
    rescue Signet::AuthorizationError => e
      redirect_to admin_user_path(@user), alert: "Failed to refresh token for #{credential.email}: #{e.message}"
    rescue => e
      redirect_to admin_user_path(@user), alert: "Failed to refresh token: #{e.message}"
    end

    def force_calendar_sync
      authorize @user, :force_calendar_sync?

      unless @user.google_credential&.google_calendar
        redirect_to admin_user_path(@user), alert: "User does not have a Google Calendar set up."
        return
      end

      GoogleCalendarSyncJob.perform_later(@user, force: true)
      redirect_to admin_user_path(@user), notice: "Calendar sync queued for #{@user.email}."
    rescue => e
      redirect_to admin_user_path(@user), alert: "Failed to queue calendar sync: #{e.message}"
    end

    def add_friend
      authorize @user, :manage_friendships?

      friend_id = params[:friend_id]
      if friend_id.blank?
        redirect_to admin_user_path(@user), alert: "Friend ID is required."
        return
      end

      friend = User.find_by_public_id(friend_id)
      if friend.nil?
        redirect_to admin_user_path(@user), alert: "User not found with ID: #{friend_id}"
        return
      end

      if friend.id == @user.id
        redirect_to admin_user_path(@user), alert: "Cannot add user as their own friend."
        return
      end

      existing = Friendship.where(
        "(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
        @user.id, friend.id, friend.id, @user.id
      ).first

      if existing
        if existing.accepted?
          redirect_to admin_user_path(@user), alert: "#{friend.full_name} is already a friend."
        else
          existing.accepted!
          redirect_to admin_user_path(@user), notice: "Accepted existing friend request with #{friend.full_name}."
        end
        return
      end

      Friendship.create!(requester: @user, addressee: friend, status: :accepted)
      redirect_to admin_user_path(@user), notice: "Added #{friend.full_name} as a friend."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_user_path(@user), alert: "Failed to add friend: #{e.message}"
    end

    def remove_friend
      authorize @user, :manage_friendships?

      friend = User.find_by_public_id(params[:friend_id])

      if friend.nil?
        redirect_to admin_user_path(@user), alert: "User not found."
        return
      end

      friendship = Friendship.where(
        "(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
        @user.id, friend.id, friend.id, @user.id
      ).first

      if friendship.nil?
        redirect_to admin_user_path(@user), alert: "Friendship not found."
        return
      end

      friendship.destroy!
      redirect_to admin_user_path(@user), notice: "Removed #{friend.full_name} as a friend."
    end

    private

    def set_user
      @user = if params[:id].start_with?("usr_")
                User.find_by_public_id(params[:id])
              elsif params[:id].match?(/^[a-z0-9]+$/) && !params[:id].match?(/^\d+$/)
                User.find_by_hashid(params[:id])
              else
                User.find(params[:id])
              end

      raise ActiveRecord::RecordNotFound unless @user
    end

    def user_params
      permitted = [:first_name, :last_name]
      permitted << :access_level if policy(@user).edit_access_level?
      params.expect(user: permitted)
    end
  end
end
