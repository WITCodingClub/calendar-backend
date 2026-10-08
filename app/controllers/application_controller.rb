# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Authentication

  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # A guest who signed in from a meeting link goes back to that link. The
  # session holds only a /meet/ path, which MeetingLinksController sets.
  def after_sign_in_path_for(resource)
    return_to = session.delete(MeetingLinksController::RETURN_TO_KEY).to_s
    return return_to if return_to.start_with?("/meet/")

    resource.admin_access? ? admin_root_path : dashboard_root_path
  end

  def admin_unauthorized
    if user_signed_in?
      redirect_to dashboard_root_path, alert: "You don't have permission to access that page."
    else
      redirect_to new_user_session_path
    end
  end

  private

  # Audits1984 (mounted at /admin/audits) calls this to find the auditor.
  def find_current_auditor
    current_user if current_user&.admin_access?
  end

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back_or_to unauthorized_path
  end
end
