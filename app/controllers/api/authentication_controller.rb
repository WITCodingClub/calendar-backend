module Api
  class AuthenticationController < ApplicationController
    skip_before_action :verify_authenticity_token

    # POST /api/login
    def login
      user = User.find_by(email: params[:email])

      if user&.valid_password?(params[:password])
        token = JsonWebTokenService.encode(user_id: user.id)
        render json: {
          token: token,
          user: {
            id: user.id,
            email: user.email,
            access_level: user.access_level
          }
        }, status: :ok
      else
        render json: { error: "Invalid email or password" }, status: :unauthorized
      end
    end

    # POST /api/signup
    def signup
      user = User.new(user_params)

      if user.save
        token = JsonWebTokenService.encode(user_id: user.id)
        render json: {
          token: token,
          user: {
            id: user.id,
            email: user.email,
            access_level: user.access_level
          }
        }, status: :created
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/request_magic_link
    def request_magic_link
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      # Find or create user (for passwordless, we auto-create accounts)
      user = User.find_or_create_by(email: email.downcase.strip) do |u|
        # Generate a random password for new users (they won't use it)
        u.password = SecureRandom.urlsafe_base64(32)
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

    private

    def user_params
      params.permit(:email, :password, :password_confirmation)
    end
  end
end
