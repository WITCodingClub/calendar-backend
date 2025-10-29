class SessionsController < ApplicationController
  layout "auth"
  before_action :redirect_if_authenticated, only: [:new]

  # GET /users/sign_in
  def new
    # Show the magic link request form
  end

  # DELETE /users/sign_out
  def destroy
    sign_out
    redirect_to new_user_session_path, notice: "Signed out successfully."
  end

  private

  def redirect_if_authenticated
    if user_signed_in?
      redirect_to after_sign_in_path
    end
  end

  def after_sign_in_path
    if current_user.admin_access?
      admin_root_path
    else
      dashboard_path
    end
  end
end
