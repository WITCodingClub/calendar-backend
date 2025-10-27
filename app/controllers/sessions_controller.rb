class SessionsController < ApplicationController
  layout "auth"

  # GET /users/sign_in
  def new
    # Show the magic link request form
  end

  # DELETE /users/sign_out
  def destroy
    sign_out
    redirect_to new_user_session_path, notice: "Signed out successfully."
  end
end
