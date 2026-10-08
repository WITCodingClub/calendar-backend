# frozen_string_literal: true

module Admin
  class ApplicationController < ::ApplicationController
    layout "admin"

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    before_action :authenticate_admin!

    def index
      @dashboard = Admin::Dashboard.new(current_user)
    end

    private

    def authenticate_admin!
      unless user_signed_in?
        redirect_to new_user_session_path, alert: "Please sign in to continue."
        return
      end

      redirect_to unauthorized_path unless current_user.admin_access?
    end

    def user_not_authorized
      flash[:alert] = "You are not authorized to perform this action."
      redirect_to unauthorized_path
    end
  end
end
