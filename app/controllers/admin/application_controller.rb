module Admin
  class ApplicationController < ::ApplicationController
    layout "admin"
    include Pundit
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    before_action :require_admin

    # Shared admin logic here
    def index
      @current_user = current_user
      @users_count = User.count
      @admin_count = User.where(access_level: [:admin, :super_admin, :owner]).count
      @active_sessions_count = 1 # Placeholder - update with actual session tracking if available
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