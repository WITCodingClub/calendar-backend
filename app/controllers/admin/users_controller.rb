# frozen_string_literal: true

module Admin
  class UsersController < Admin::ApplicationController
    before_action :set_user, only: [:show, :edit, :update, :destroy, :revoke_oauth_credential, :refresh_oauth_credential, :toggle_support_flag, :force_calendar_sync]

    # Support tool flags that can be toggled via admin UI
    SUPPORT_FLAGS = {
      env_switcher: FlipperFlags::ENV_SWITCHER,
      debug_mode: FlipperFlags::DEBUG_MODE
    }.freeze

    def index
      @users = policy_scope(User).order(created_at: :desc)

      if params[:search].present?
        search_term = params[:search].strip

        # Check if search term is numeric (for ID search)
        if search_term.match?(/^\d+$/)
          @users = @users.where(id: search_term.to_i)
        else
          # Search by email (through emails table) or concatenated first+last name
          @users = @users.joins(:emails).where(
            "emails.email ILIKE :search OR " \
            "CONCAT(users.first_name, users.last_name) ILIKE :search OR " \
            "CONCAT(users.first_name, ' ', users.last_name) ILIKE :search",
            search: "%#{search_term}%"
          ).distinct
        end
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

      # Eager load oauth credentials with calendar
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

      if credential.refresh_token.blank?
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

    def toggle_support_flag
      authorize @user, :toggle_support_flag?

      flag_key = params[:flag]&.to_sym
      unless SUPPORT_FLAGS.key?(flag_key)
        redirect_to admin_user_path(@user), alert: "Unknown support flag: #{params[:flag]}"
        return
      end

      flipper_flag = SUPPORT_FLAGS[flag_key]
      flag_name = flag_key.to_s.titleize

      if Flipper.enabled?(flipper_flag, @user)
        Flipper.disable_actor(flipper_flag, @user)
        redirect_to admin_user_path(@user), notice: "#{flag_name} disabled for #{@user.email}."
      else
        Flipper.enable_actor(flipper_flag, @user)
        redirect_to admin_user_path(@user), notice: "#{flag_name} enabled for #{@user.email}."
      end
    rescue => e
      Rails.logger.error("Error toggling support flag: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to toggle #{flag_name}: #{e.message}"
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
      # Try different formats: full public_id, hashid only, or integer ID
      @user = if params[:id].start_with?("usr_")
                # Full public_id format
                User.find_by_public_id(params[:id])
              elsif params[:id].match?(/^[a-z0-9]+$/) && !params[:id].match?(/^\d+$/)
                # Hashid only (from to_param)
                User.find_by_hashid(params[:id])
              elsif params[:id].match?(/^\d+$/)
                # Integer ID
                User.find(params[:id])
              end

      raise ActiveRecord::RecordNotFound unless @user
    end

    def user_params
      permitted = [:email, :first_name, :last_name]
      permitted << :access_level if policy(@user).edit_access_level?
      params.expect(user: permitted)
    end

  end
end
