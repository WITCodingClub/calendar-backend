# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  layout "sessions", only: [ :new ]

  before_action :redirect_if_authenticated, only: [ :new ]

  def new
    # Renders sign-in page with Google OAuth button
  end

  private

  def redirect_if_authenticated
    return unless user_signed_in?

    redirect_to current_user.admin_access? ? admin_root_path : dashboard_root_path
  end
end
