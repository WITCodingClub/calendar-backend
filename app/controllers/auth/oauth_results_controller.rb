# frozen_string_literal: true

module Auth
  class OauthResultsController < ApplicationController
    layout "sessions"

    # The result pages only show text. The confirm actions save tokens, so they
    # keep the CSRF check.
    skip_before_action :verify_authenticity_token, only: %i[success failure]

    before_action :load_pending_link, only: %i[confirm link]

    def success
      @email       = params[:email]
      @calendar_id = params[:calendar_id]
    end

    def failure
      @error = params[:error] || "Unknown error occurred"
    end

    # Names the Google account and the calendar account, so the person can see
    # whose account the link goes to before any token is saved.
    def confirm
      @google_email = @pending[:email]
      @user_email   = @user.email
    end

    def link
      pending_id = session.delete(:pending_google_link)
      OauthCredentials::AccountLink.discard_pending(pending_id)

      link        = OauthCredentials::AccountLink.new(@user, GoogleCalendar::Provider.provider_name)
      calendar_id = link.connect!(**@pending.slice(:uid, :email, :access_token, :refresh_token, :expires_at))

      redirect_to oauth_success_path(email: @pending[:email], calendar_id: calendar_id)
    rescue OauthCredentials::AccountLink::Conflict => e
      redirect_to oauth_failure_path(error: e.message)
    rescue => e
      Rails.error.report(e, handled: true, context: { user_id: @user.id })
      redirect_to oauth_failure_path(error: "Could not connect the Google account. Please try again.")
    end

    def cancel
      OauthCredentials::AccountLink.discard_pending(session.delete(:pending_google_link))

      redirect_to oauth_failure_path(error: "You cancelled the connection. No account was linked.")
    end

    private

    def load_pending_link
      @pending = OauthCredentials::AccountLink.read_pending(session[:pending_google_link])
      @user    = @pending && User.find_by(id: @pending[:user_id])
      return if @user

      session.delete(:pending_google_link)
      redirect_to oauth_failure_path(error: "This request expired. Start again from the extension or the dashboard.")
    end
  end
end
