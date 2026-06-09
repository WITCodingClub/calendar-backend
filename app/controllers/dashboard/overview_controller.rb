# frozen_string_literal: true

class Dashboard::OverviewController < Dashboard::ApplicationController
  def index
    authorize current_user, :show?

    @current_term  = Term.current
    @next_term     = Term.next
    @enrollment_count = current_user.enrollments.where(term: @current_term).count if @current_term
    @has_calendar  = current_user.oauth_credentials.joins(:google_calendar).exists?
    @notifications_disabled = current_user.notifications_disabled?
    @ics_url       = current_user.cal_url_with_extension
  end
end
