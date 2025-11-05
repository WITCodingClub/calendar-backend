# frozen_string_literal: true

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
    return unless user_signed_in?

    if current_user.admin_access?
      redirect_to admin_root_path
    else
      redirect_to unauthorized_path
    end
  end

end
