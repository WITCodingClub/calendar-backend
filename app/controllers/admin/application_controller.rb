# frozen_string_literal: true

module Admin
  class ApplicationController < ::ApplicationController
    layout "admin"
    include Pundit::Authorization

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    before_action :require_admin

    # Shared admin logic here
    def index
      @current_user = current_user
      @users_count = User.count
      @buildings_count = Building.count
      @rooms_count = Room.count
      @courses_count = Course.count
      @faculties_count = Faculty.count
      @terms_count = Term.count
      @google_calendars_count = GoogleCalendar.count
      @rmp_ratings_count = RmpRating.count
      @missing_rmp_ids_count = Faculty.where(rmp_id: nil).count
    end

    private

    def require_admin
      unless user_signed_in?
        redirect_to new_user_session_path, alert: "Please sign in to continue."
        return
      end

      return if current_user.admin_access?

      redirect_to admin_unauthorized_path

    end

    def user_not_authorized
      flash[:alert] = "You are not authorized to perform this action."
      redirect_to admin_unauthorized_path
    end

  end
end
