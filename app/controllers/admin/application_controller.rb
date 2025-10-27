module Admin
  class ApplicationController < ::ApplicationController
    include Pundit
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    before_action :require_admin

    # Shared admin logic here
    def index
      @current_user = current_user
    end

    private

    def require_admin
      unless user_signed_in?
        redirect_to new_user_session_path, alert: "Please sign in to continue."
        return
      end

      unless current_user.admin_access?
        redirect_to admin_unauthorized_path
      end
    end

    def user_not_authorized
      flash[:alert] = "You are not authorized to perform this action."
      redirect_to admin_unauthorized_path
    end
  end
end