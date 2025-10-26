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
      unless current_user&.admin? || current_user&.super_admin? || current_user&.owner?
        redirect_to root_path, alert: "You are not authorized to access this area."
      end
    end

    def user_not_authorized
      flash[:alert] = "You are not authorized to perform this action."
      redirect_to(request.referrer || root_path)
    end
  end
end