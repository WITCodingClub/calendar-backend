module Api
  class UsersController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user_from_token!, only: [:onboard]

    def onboard
      #   takes email as it's one param
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      user = User.find_or_create_by_email(email)

      # return JSON with a jwt token for the user. this token should be signed, and never expire
      token = JsonWebTokenService.encode({ user_id: user.id }, nil) # nil expiration for never expiring

      render json: { jwt: token }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to onboard user" }, status: :internal_server_error

    end


  end
end