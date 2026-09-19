# frozen_string_literal: true

# Connects a Microsoft 365 calendar with the authorization code flow and PKCE.
#
# The extension asks POST /api/user/microsoft_calendar for a start URL. The
# browser opens it, signs in at Microsoft and comes back to the callback,
# which stores the tokens as an OauthCredential and creates the calendar.
# Every step answers 404 while the Microsoft Graph provider is off.
class MicrosoftAuthController < ApplicationController
  SESSION_KEY = :microsoft_graph_oauth

  # The Microsoft account at the callback is not the person's own WIT account.
  class WrongAccountError < StandardError; end

  before_action :load_state

  # GET /auth/microsoft_graph?state=...
  def start
    code_verifier = SecureRandom.urlsafe_base64(64)
    session[SESSION_KEY] = { "nonce" => @state["nonce"], "code_verifier" => code_verifier }

    redirect_to token_client.authorize_url(state: params[:state], code_verifier: code_verifier, redirect_uri: redirect_uri),
                allow_other_host: true
  end

  # GET /auth/microsoft_graph/callback?code=...&state=...
  def callback
    pending = session.delete(SESSION_KEY)

    raise MicrosoftGraph::AuthError, "Microsoft returned #{params[:error]}" if params[:error].present?
    raise MicrosoftGraph::AuthError, "sign-in did not start in this browser" unless pending && pending["nonce"] == @state["nonce"]

    token = token_client.exchange_code(code: params.require(:code),
                                       code_verifier: pending["code_verifier"],
                                       redirect_uri: redirect_uri)
    credential  = save_credential(token)
    calendar_id = MicrosoftGraphCalendarService.new(@user, credential: credential).create_or_get_course_calendar

    GoogleCalendarSyncJob.perform_later(@user, force: true) if @user.enrollments.any?

    redirect_to "/oauth/success?email=#{CGI.escape(credential.email)}&calendar_id=#{CGI.escape(calendar_id)}"
  rescue WrongAccountError
    redirect_to "/oauth/failure?error=#{CGI.escape("Sign in with your own WIT Microsoft account (#{@user.email}).")}"
  rescue MicrosoftGraph::Error, ActionController::ParameterMissing, ActiveRecord::RecordInvalid => e
    Rails.logger.error("Microsoft calendar OAuth error: #{e.class}: #{e.message}")
    redirect_to "/oauth/failure?error=#{CGI.escape('Could not connect the Microsoft calendar. Please try again.')}"
  end

  private

  def load_state
    @state = MicrosoftGraph::OauthState.verify(params[:state])
    @user  = @state && User.find_by(id: @state["user_id"])
    return if @user && MicrosoftGraph.enabled_for?(@user)

    head :not_found
  end

  def save_credential(token)
    claims = token.claims || {}
    uid    = claims["oid"].presence || claims["sub"].presence
    email  = claims["email"].presence || claims["preferred_username"].presence
    raise MicrosoftGraph::AuthError, "Microsoft returned no account id or email" if uid.blank? || email.blank?
    raise WrongAccountError unless own_account?(email)

    credential = @user.oauth_credentials.find_or_initialize_by(provider: "microsoft", uid: uid)
    credential.email            = email
    credential.access_token     = token.access_token
    credential.refresh_token    = token.refresh_token if token.refresh_token.present?
    credential.token_expires_at = token.expires_at
    # A new sign-in replaces a refresh token that Microsoft refused.
    credential.metadata         = (credential.metadata || {}).except("token_revoked", "token_revoked_at", "revocation_reason")
    credential.save!
    credential
  end

  # The state names the person, but nothing proves that the browser at the
  # callback belongs to them: the extension opens this flow in a tab that has
  # no session. A person could send their own start URL to someone else, and
  # that person's mailbox would land on the sender's account. So the Microsoft
  # account must be the person's own WIT account. The Google flow makes the
  # same check with the email in its state.
  #
  # Development skips the check, so a personal Outlook.com account can test
  # the provider before WIT IT grants consent.
  def own_account?(email)
    return true if Rails.env.development?

    email.to_s.strip.casecmp?(@user.email.to_s)
  end

  def redirect_uri
    MicrosoftGraph.config[:redirect_uri] || "#{request.base_url}/auth/microsoft_graph/callback"
  end

  def token_client
    @token_client ||= MicrosoftGraph::TokenClient.new
  end
end
