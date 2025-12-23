# frozen_string_literal: true

module Admin
  class UsersController < Admin::ApplicationController
    before_action :set_user, only: [:show, :edit, :update, :destroy, :revoke_oauth_credential, :refresh_oauth_credential, :enable_beta, :disable_beta, :force_calendar_sync]

    BETA_FEATURE_FLAG = FlipperFlags::V1

    def index
      @users = policy_scope(User).order(created_at: :desc)

      if params[:search].present?
        @users = @users.where("email ILIKE ?", "%#{params[:search]}%")
      end

      @users = @users.page(params[:page]).per(5)

      # For Turbo Frame requests, only render the frame
      return unless turbo_frame_request?

      render partial: "users_table"

    end

    def show
      authorize @user

      # Eager load enrollments with their associations for the view
      @enrollments_by_term = @user.enrollments
                                  .includes({ course: :faculties }, :term)
                                  .joins(:term)
                                  .order("terms.year DESC, terms.season DESC")
                                  .group_by(&:term)

      # Eager load oauth credentials with calendar and event counts
      @oauth_credentials = @user.oauth_credentials
                                .includes(:google_calendar)
                                .left_joins(google_calendar: :google_calendar_events)
                                .select("oauth_credentials.*, COUNT(google_calendar_events.id) as events_count")
                                .group("oauth_credentials.id")
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
        render :edit, status: :unprocessable_entity
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
      credential_email = credential.email

      # Queue the revocation job
      RevokeOauthCredentialJob.perform_later(credential.id)

      redirect_to admin_user_path(@user), notice: "OAuth credential for #{credential_email} is being revoked."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_user_path(@user), alert: "OAuth credential not found."
    end

    def refresh_oauth_credential
      authorize @user, :refresh_oauth_credential?
      credential = @user.oauth_credentials.find(params[:credential_id])

      unless credential.refresh_token.present?
        redirect_to admin_user_path(@user), alert: "No refresh token available for #{credential.email}. User needs to re-authenticate."
        return
      end

      # Build Google credentials and refresh
      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id: Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        refresh_token: credential.refresh_token,
        scope: ["https://www.googleapis.com/auth/calendar"]
      )

      credentials.refresh!

      credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.current + credentials.expires_in.seconds
      )

      redirect_to admin_user_path(@user), notice: "OAuth token refreshed for #{credential.email}."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_user_path(@user), alert: "OAuth credential not found."
    rescue Signet::AuthorizationError => e
      Rails.logger.error("Error refreshing OAuth token: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to refresh token for #{credential.email}. User may need to re-authenticate."
    rescue => e
      Rails.logger.error("Error refreshing OAuth token: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to refresh token: #{e.message}"
    end

    def enable_beta
      authorize @user, :enable_beta?

      Flipper.enable_actor(BETA_FEATURE_FLAG, @user)
      redirect_to admin_user_path(@user), notice: "#{@user.email} has been added to the beta test group."
    rescue => e
      Rails.logger.error("Error adding user to beta: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to add user to beta: #{e.message}"
    end

    def disable_beta
      authorize @user, :disable_beta?

      Flipper.disable_actor(BETA_FEATURE_FLAG, @user)
      redirect_to admin_user_path(@user), notice: "Beta tester access removed for #{@user.email}."
    rescue => e
      Rails.logger.error("Error removing user from beta: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to remove user from beta: #{e.message}"
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
      Rails.logger.error("Error queueing calendar sync: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to queue calendar sync: #{e.message}"
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.expect(user: [:email, :first_name, :last_name, :access_level])
    end

  end
end
