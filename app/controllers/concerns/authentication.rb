# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  def require_admin!
    return if current_user&.admin_access?

    redirect_to unauthorized_path, alert: "You don't have permission to access this page."
  end
end
