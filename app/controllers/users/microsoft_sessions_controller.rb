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

    def create
      auth = request.env["omniauth.auth"]
      return head(:not_found) unless auth

      result = MicrosoftSignIn::Authenticator.call(auth)

      unless result.success?
        redirect_to new_user_session_path, alert: result.error
        return
      end

      redirect_to sign_in_with_session!(result.user), notice: "Welcome, #{result.user.first_name}!"
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.error.report(e, handled: true)
      redirect_to new_user_session_path, alert: "Failed to sign in with Microsoft. Please try again."
    end

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
