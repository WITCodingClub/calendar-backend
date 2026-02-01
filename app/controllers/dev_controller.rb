# frozen_string_literal: true

# Controller for development-only utilities
# Only accessible in Rails.env.development?
class DevController < ApplicationController
  # No authentication or browser checks required for dev utilities
  skip_before_action :verify_authenticity_token, only: :login

  # Override browser guard to allow any browser in dev mode
  def self.allow_browser(**options)
    # Skip browser check in development
  end

  # Quick login bypass for development
  # Usage: GET /dev/login/mayonej@wit.edu
  def login
    # Security: Only works in development
    unless Rails.env.development?
      head :not_found
      return
    end

    email = params[:email]

    # Security: Hardcoded whitelist of allowed emails
    unless email == "mayonej@wit.edu"
      flash[:alert] = "Dev login not allowed for this email"
      redirect_to root_path
      return
    end

    # Try to find existing user, or create with placeholder name
    user = User.find_by_email(email)
    unless user
      user = User.find_or_create_by_email(email, "Dev", "User")
      user.update!(access_level: :owner) if email == "mayonej@wit.edu"
    end

    # Ensure user has admin access
    unless user.admin_access?
      flash[:alert] = "User #{email} does not have admin access"
      redirect_to root_path
      return
    end

    sign_in(user)

    # Verify session was set
    Rails.logger.debug { "DevController: Set session[:user_id] = #{session[:user_id]}" }
    Rails.logger.debug { "DevController: user_signed_in? = #{user_signed_in?}" }
    Rails.logger.debug { "DevController: current_user = #{current_user.inspect}" }

    flash[:notice] = "Logged in as #{user.email} (dev mode)"
    redirect_to admin_root_path, allow_other_host: false
  end

end
