class Admin::ServiceAccountController < Admin::ApplicationController
  skip_before_action :require_admin # We have our own authorization
  before_action :require_owner!, except: [:callback]

  def index
    # Show current service account status
    @service_account_email = Rails.application.credentials.dig(:google, :service_account_email)
    @has_oauth_token = Rails.application.credentials.dig(:google, :service_account_oauth_refresh_token).present?
  end

  def authorize
    # Initiate OAuth flow for service account email using Signet for full control
    require 'signet/oauth_2/client'
    require 'google/apis/calendar_v3'

    # Store a secure random state token for CSRF protection
    session[:oauth_state] = SecureRandom.hex(32)
    session[:oauth_initiator_user_id] = current_user.id # Track who initiated the OAuth flow

    # Build full callback URL
    callback_url = "#{request.base_url}/admin/oauth/callback"

    # Manually construct OAuth client to control redirect_uri
    client = Signet::OAuth2::Client.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      authorization_uri: 'https://accounts.google.com/o/oauth2/auth',
      token_credential_uri: 'https://oauth2.googleapis.com/token',
      scope: [Google::Apis::CalendarV3::AUTH_CALENDAR],
      redirect_uri: callback_url,
      state: session[:oauth_state],
      additional_parameters: {
        access_type: 'offline',  # Required to get refresh token
        prompt: 'consent'         # Force consent screen to ensure refresh token
      }
    )

    authorization_url = client.authorization_uri.to_s

    redirect_to authorization_url, allow_other_host: true
  end

  def callback
    # Verify state to prevent CSRF
    unless params[:state] == session[:oauth_state]
      flash[:alert] = 'Invalid OAuth state. Please try again.'
      redirect_to admin_service_account_index_path
      return
    end

    # Verify the user who initiated the flow is an owner
    initiator_user_id = session.delete(:oauth_initiator_user_id)
    initiator_user = User.find_by(id: initiator_user_id)

    unless initiator_user&.owner?
      flash[:alert] = 'Access denied. Only owners can complete this OAuth flow.'
      redirect_to root_path
      return
    end

    session.delete(:oauth_state)

    # Exchange authorization code for tokens using Signet
    require 'signet/oauth_2/client'

    # Build the same callback URL as in authorize
    callback_url = "#{request.base_url}/admin/oauth/callback"

    # Create OAuth client
    client = Signet::OAuth2::Client.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      token_credential_uri: 'https://oauth2.googleapis.com/token',
      redirect_uri: callback_url,
      code: params[:code]
    )

    # Fetch the access token
    client.fetch_access_token!

    if client.refresh_token.present?
      @refresh_token = client.refresh_token
      @access_token = client.access_token
      render :success
    else
      flash[:alert] = 'No refresh token received. You may need to revoke access and try again.'
      redirect_to admin_service_account_index_path
    end
  rescue => e
    Rails.logger.error("Service account OAuth error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    flash[:alert] = "OAuth error: #{e.message}"
    redirect_to admin_service_account_index_path
  end

  def revoke
    # Instructions for revoking access
    flash[:info] = 'To revoke access, visit: https://myaccount.google.com/permissions'
    redirect_to admin_service_account_index_path
  end

  private

  def require_owner!
    unless current_user&.owner?
      flash[:alert] = 'Access denied. Owner role required.'
      redirect_to admin_root_path
    end
  end

  # Uncomment this method if you want to auto-update credentials
  # def update_credentials_with_refresh_token(refresh_token)
  #   # This would require implementing a way to update Rails credentials programmatically
  #   # For security, it's better to manually add it to credentials
  # end
end
