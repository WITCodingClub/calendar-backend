# frozen_string_literal: true

class OauthController < ApplicationController
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

  # GET /oauth/confirm
  # Names the Google account and the calendar account, so the person can see
  # whose account the link goes to before any token is saved.
  def confirm
    @google_email = @pending[:email]
    @user_email   = @user.email
  end

  # POST /oauth/confirm
  def link
    pending_id = session.delete(:pending_google_link)
    GoogleAccountLinkService.discard_pending(pending_id)

    calendar_id = GoogleAccountLinkService.new(@user).connect!(**@pending.slice(:uid, :email, :access_token, :refresh_token, :expires_at))

    redirect_to "/oauth/success?email=#{CGI.escape(@pending[:email])}&calendar_id=#{calendar_id}"
  rescue GoogleAccountLinkService::Conflict => e
    redirect_to "/oauth/failure?error=#{CGI.escape(e.message)}"
  rescue => e
    Rails.logger.error("Google account link error: #{e.class}: #{e.message}")
    redirect_to "/oauth/failure?error=#{CGI.escape('Could not connect the Google account. Please try again.')}"
  end

  # DELETE /oauth/confirm
  def cancel
    GoogleAccountLinkService.discard_pending(session.delete(:pending_google_link))

    redirect_to "/oauth/failure?error=#{CGI.escape('You cancelled the connection. No account was linked.')}"
  end

  private

  def load_pending_link
    @pending = GoogleAccountLinkService.read_pending(session[:pending_google_link])
    @user    = @pending && User.find_by(id: @pending[:user_id])
    return if @user

    session.delete(:pending_google_link)
    redirect_to "/oauth/failure?error=#{CGI.escape('This request expired. Start again from the extension or the dashboard.')}"
  end
end
