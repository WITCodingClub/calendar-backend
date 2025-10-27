class MagicLinkController < ApplicationController
  skip_before_action :verify_authenticity_token
  layout "auth"

  # POST /request_magic_link
  def request_link
    email = params[:email]

    if email.blank?
      flash[:error] = "Email is required"
      redirect_to new_user_session_path and return
    end

    # Find or create user (for passwordless, we auto-create accounts)
    user = User.find_or_create_by(email: email.downcase.strip)

    # Create magic link
    magic_link = user.magic_links.create!

    # Send email
    MagicLinkMailer.send_link(magic_link).deliver_later

    redirect_to magic_link_sent_path
  rescue StandardError => e
    Rails.logger.error("Error sending magic link: #{e.message}")
    flash[:error] = "Failed to send magic link"
    redirect_to new_user_session_path
  end

  # GET /magic_link/sent
  def sent
    # Shows confirmation page
  end

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

    # Sign in the user with Devise
    sign_in(magic_link.user)

    # Generate JWT token for API use
    jwt_token = JsonWebTokenService.encode(user_id: magic_link.user.id)

    # Store token and user info for the view
    @jwt_token = jwt_token
    @user = magic_link.user

    render :success
  end
end
