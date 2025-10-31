module Api
  class UserController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token

    def request_gcal
      @user = current_user
      # Execute synchronously for Chrome extension compatibility
      GoogleCalendarCreateJob.perform_now(@user.id)
      GoogleCalendarSyncJob.perform_now(@user)

      render json: { message: "Google Calendar created and synced successfully" }, status: :ok
    end

    def request_ics
      @user = current_user
      @user.generate_calendar_token
      render json: { cal_url: @user.cal_url }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error generating ICS URL: #{e.message}")
      render json: { error: "Failed to generate ICS URL" }, status: :internal_server_error
    end

  end
end