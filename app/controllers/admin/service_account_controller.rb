# frozen_string_literal: true

module Admin
  class ServiceAccountController < Admin::ApplicationController
    before_action :require_owner!, except: [ :callback ]

    def index
      @service_account_email = Rails.application.credentials.dig(:google, :service_account_email)
      @has_oauth_token = Rails.application.credentials.dig(:google, :service_account_oauth_refresh_token).present?
    end

    def authorize
      require "signet/oauth_2/client"
      require "google/apis/calendar_v3"

      session[:oauth_state] = SecureRandom.hex(32)
      session[:oauth_initiator_user_id] = current_user.id

      callback_url = "#{app_base_url}/admin/oauth/callback"

      client = Signet::OAuth2::Client.new(
        client_id: Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        authorization_uri: "https://accounts.google.com/o/oauth2/auth",
        token_credential_uri: "https://oauth2.googleapis.com/token",
        scope: [ Google::Apis::CalendarV3::AUTH_CALENDAR ],
        redirect_uri: callback_url,
        state: session[:oauth_state],
        additional_parameters: {
          access_type: "offline",
          prompt: "consent"
        }
      )

      redirect_to client.authorization_uri.to_s, allow_other_host: true
    end

    def callback
      unless params[:state] == session[:oauth_state]
        flash[:alert] = "Invalid OAuth state. Please try again."
        redirect_to admin_service_account_index_path
        return
      end

      initiator_user_id = session.delete(:oauth_initiator_user_id)
      initiator_user = User.find_by(id: initiator_user_id)

      unless initiator_user&.owner?
        flash[:alert] = "Access denied. Only owners can complete this OAuth flow."
        redirect_to root_path
        return
      end

      session.delete(:oauth_state)

      require "signet/oauth_2/client"

      callback_url = "#{app_base_url}/admin/oauth/callback"

      client = Signet::OAuth2::Client.new(
        client_id: Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        token_credential_uri: "https://oauth2.googleapis.com/token",
        redirect_uri: callback_url,
        code: params[:code]
      )

      client.fetch_access_token!

      if client.refresh_token.present?
        @refresh_token = client.refresh_token
        @access_token = client.access_token
        render :success
      else
        flash[:alert] = "No refresh token received. You may need to revoke access and try again."
        redirect_to admin_service_account_index_path
      end
    rescue => e
      Rails.logger.error("Service account OAuth error: #{e.message}")
      flash[:alert] = "OAuth error: #{e.message}"
      redirect_to admin_service_account_index_path
    end

    def revoke
      flash[:info] = "To revoke access, visit: https://myaccount.google.com/permissions"
      redirect_to admin_service_account_index_path
    end

    private

    def app_base_url
      if (host = ENV["APPLICATION_HOST"])
        "#{request.protocol}#{host}"
      else
        request.base_url
      end
    end

    def require_owner!
      return if current_user&.owner?

      flash[:alert] = "Access denied. Owner role required."
      redirect_to admin_root_path
    end
  end
end
