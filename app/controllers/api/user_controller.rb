module Api
  class UserController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token

    def request_gcal
      @user = current_user
      @user.create_or_get_course_calendar
      @user.sync_course_schedule

      render json: { message: "Google Calendar Created, Sync Inititalized" }, status: :ok
    end

    def request_ics
      @user = current_user
      @user.generate_calendar_token if @user.calendar_token.blank?
      render json: { cal_url: current_user.cal_url }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error generating ICS URL: #{e.message}")
      render json: { error: "Failed to generate ICS URL" }, status: :internal_server_error
    end

  end
end