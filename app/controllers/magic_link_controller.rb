class MagicLinkController < ApplicationController
  skip_before_action :verify_authenticity_token

  # GET /magic_link/verify?token=xxx
  def verify
    token_param = params[:token]

    if token_param.blank?
      @error = "No token provided"
      render :error and return
    end

    magic_link = MagicLink.find_by(token: token_param)

    if magic_link.nil?
      @error = "Invalid magic link"
      render :error and return
    end

    if magic_link.expired?
      @error = "This magic link has expired. Please request a new one."
      render :error and return
    end

    if magic_link.used?
      @error = "This magic link has already been used. Please request a new one."
      render :error and return
    end

    # Mark as used
    magic_link.mark_as_used!

    # Generate JWT token
    jwt_token = JsonWebTokenService.encode(user_id: magic_link.user.id)

    # Store token and user info for the view
    @jwt_token = jwt_token
    @user = magic_link.user

    render :success
  end
end
