# frozen_string_literal: true

module Users
  # Signing in to the dashboard with a WIT Microsoft account.
  #
  # OmniAuth starts the sign-in on POST /auth/microsoft and handles the
  # callback. This controller gets the verified auth hash and ends in a Devise
  # cookie session, the same as the Google dashboard sign-in. Like Google and
  # the dashboard passkey sign-in, it issues no API token and no UserSession.
  #
  # Every action answers 404 while MicrosoftSignIn.enabled? is false.
  class MicrosoftSessionsController < ApplicationController
    before_action :require_microsoft_sign_in

    # GET /auth/microsoft/callback
    def create
      auth = request.env["omniauth.auth"]
      return head(:not_found) unless auth

      result = MicrosoftSignIn::Authenticator.call(auth)

      unless result.success?
        redirect_to new_user_session_path, alert: result.error
        return
      end

      user = result.user
      # Stay signed in past the :timeoutable idle limit, as the Google sign-in does.
      user.remember_me = true
      sign_in(:user, user)

      redirect_to after_sign_in_path_for(user), notice: "Welcome, #{user.first_name}!"
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.error("Microsoft sign-in error: #{e.class}: #{e.message}")
      redirect_to new_user_session_path, alert: "Failed to sign in with Microsoft. Please try again."
    end

    # GET /auth/failure?strategy=microsoft
    #
    # OmniAuth sends a failed or cancelled sign-in here.
    def failure
      redirect_to new_user_session_path, alert: "Failed to sign in with Microsoft. Please try again."
    end

    private

    def require_microsoft_sign_in
      head :not_found unless MicrosoftSignIn.enabled?
    end
  end
end
