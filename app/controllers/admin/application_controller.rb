# frozen_string_literal: true

module Admin
  class ApplicationController < ::ApplicationController
    layout "admin"

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    before_action :authenticate_admin!
    after_action :verify_authorized

    def index
      # The dashboard shows no record. authenticate_admin! already guards it.
      skip_authorization

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

    # The rows where any of the columns contains the search text. A % or _ in
    # the text matches itself, not any characters.
    def search_scope(scope, *columns, term: params[:search])
      return scope if term.blank?

      pattern = "%#{ApplicationRecord.sanitize_sql_like(term.to_s.strip)}%"
      scope.where(columns.map { |column| "#{column} ILIKE :pattern" }.join(" OR "), pattern: pattern)
    end

    def user_not_authorized
      flash[:alert] = "You are not authorized to perform this action."
      redirect_to unauthorized_path
    end
  end
end
