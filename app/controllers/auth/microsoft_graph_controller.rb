# frozen_string_literal: true

module Auth
  # Connects a Microsoft 365 calendar with the authorization code flow and PKCE.
  #
  # The extension asks POST /api/user/microsoft_calendar for a start URL. The
  # browser opens it, signs in at Microsoft and comes back to the callback,
  # which stores the tokens as an OauthCredential and creates the calendar.
  # Every step answers 404 while the Microsoft Graph provider is off.
  class MicrosoftGraphController < ApplicationController
    SESSION_KEY = :microsoft_graph_oauth

    # The Microsoft account at the callback is not the person's own WIT account.
    class WrongAccountError < StandardError; end

    before_action :load_state

    def start
      code_verifier = SecureRandom.urlsafe_base64(64)
      session[SESSION_KEY] = { "nonce" => @state["nonce"], "code_verifier" => code_verifier }

      redirect_to token_client.authorize_url(state: params[:state], code_verifier: code_verifier, redirect_uri: redirect_uri),
                  allow_other_host: true
    end

    def callback
      pending = session.delete(SESSION_KEY)

      raise MicrosoftGraph::AuthError, "Microsoft returned #{params[:error]}" if params[:error].present?
      raise MicrosoftGraph::AuthError, "sign-in did not start in this browser" unless pending && pending["nonce"] == @state["nonce"]

      token = token_client.exchange_code(code: params.require(:code),
                                         code_verifier: pending["code_verifier"],
                                         redirect_uri: redirect_uri)
      account     = account_from(token)
      calendar_id = OauthCredentials::AccountLink.new(@user, MicrosoftGraph::CalendarProvider.provider_name)
                                                 .connect!(**account, calendar: { placement: @state["placement"] })

      redirect_to oauth_success_path(email: account[:email], calendar_id: calendar_id)
    rescue WrongAccountError
      redirect_to oauth_failure_path(error: "Sign in with your own WIT Microsoft account (#{@user.email}).")
    rescue OauthCredentials::AccountLink::Conflict => e
      redirect_to oauth_failure_path(error: e.message)
    rescue MicrosoftGraph::Error, ActionController::ParameterMissing, ActiveRecord::RecordInvalid => e
      Rails.error.report(e, handled: true, context: { user_id: @user&.id })
      redirect_to oauth_failure_path(error: "Could not connect the Microsoft calendar. Please try again.")
    end

    private

    def load_state
      @state = MicrosoftGraph::OauthState.verify(params[:state])
      @user  = @state && User.find_by(id: @state["user_id"])
      return if @user && MicrosoftGraph.enabled_for?(@user)

      head :not_found
    end

    def account_from(token)
      claims = token.claims || {}
      uid    = claims["oid"].presence || claims["sub"].presence
      email  = claims["email"].presence || claims["preferred_username"].presence
      raise MicrosoftGraph::AuthError, "Microsoft returned no account id or email" if uid.blank? || email.blank?
      raise WrongAccountError unless own_account?(email)

      { uid: uid, email: email, access_token: token.access_token, refresh_token: token.refresh_token, expires_at: token.expires_at }
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
end
