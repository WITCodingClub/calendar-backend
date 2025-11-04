# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    private

    def require_admin!
      return if current_user&.admin_access?

      redirect_to admin_unauthorized_path, alert: "You don't have permission to access this page."

    end

  end
end
