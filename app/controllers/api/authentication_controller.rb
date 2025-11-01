module Api
  class AuthenticationController < ApplicationController
    skip_before_action :verify_authenticity_token

    # POST /api/login
    # Deprecated: Use Google OAuth instead
    def login
      render json: {
        error: "Password authentication is disabled. Please use Google Sign-In."
      }, status: :unauthorized
    end

    # POST /api/signup
    # Deprecated: Use Google OAuth instead
    def signup
      render json: {
        error: "Password registration is disabled. Please use Google Sign-In."
      }, status: :unauthorized
    end

    # POST /api/request_magic_link
    def request_magic_link
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      # Validate email domain
      unless email.downcase.strip.end_with?("@wit.edu")
        render json: { error: "Only @wit.edu email addresses are allowed" }, status: :bad_request
        return
      end

      # Find existing user (no longer auto-create accounts)
      user = User.find_by_email(email.downcase.strip)

      # Check if user exists and is an admin
      unless user&.admin_access?
        render json: { error: "Magic link authentication is only available for administrators. Please use Google Sign-In." }, status: :forbidden
        return
      end

      # Create magic link
      magic_link = user.magic_links.create!

      # Send email
      MagicLinkMailer.send_link(magic_link).deliver_later

      render json: {
        message: "Magic link sent! Check your email."
      }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error sending magic link: #{e.message}")
      render json: { error: "Failed to send magic link" }, status: :internal_server_error
    end

  end
end
