# frozen_string_literal: true

class Dashboard::NotificationsController < Dashboard::ApplicationController
  def show
    authorize current_user, :show?
  end

  def update
    authorize current_user, :update?

    if params[:disable] == "true"
      current_user.disable_notifications!
      GoogleCalendarSyncJob.perform_later(current_user, force: true)
      redirect_to dashboard_notifications_path, notice: "Notifications disabled."
    else
      current_user.enable_notifications!
      GoogleCalendarSyncJob.perform_later(current_user, force: true)
      redirect_to dashboard_notifications_path, notice: "Notifications enabled."
    end
  end
end
