# frozen_string_literal: true

module Users
  # Signing in to the dashboard with a passkey.
  #
  # Same credential and same ceremony as the extension uses, but it ends
  # somewhere different: the extension wants a token, and the dashboard wants a
  # Devise cookie session. That is the whole reason this is not the API
  # controller.
  #
  # Nothing here creates an account. A passkey only exists on an account that
  # already signed in with its WIT Google account, so this widens who can get in
  # not at all — it only saves them the Google round trip.
  class PasskeySessionsController < ApplicationController
    # The ceremony runs on this page, so the request carries the usual CSRF
    # token; no need to skip verification the way the token API does.

    def options
      render json: Passkeys::Authentication.options, status: :ok
    end

    def create
      passkey = Passkeys::Authentication.verify!(handle: params[:handle], params: params)

      render json: { redirect_to: sign_in_with_session!(passkey.user) }, status: :ok
    rescue Passkeys::Failed => e
      render json: { error: e.message }, status: :unauthorized
    rescue ActionController::ParameterMissing
      render json: { error: "Missing passkey credential" }, status: :bad_request
    end
  end
end
