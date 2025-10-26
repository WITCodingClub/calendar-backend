module Api
  class CourseEventsController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token

    def process_events
      events = params[:events] || params[:_json]

      if events.blank?
        render json: { error: "No events provided" }, status: :bad_request
        return
      end

      # Process events using the service with the current user
      CourseEventsProcessorService.new(events, current_user).process

      render json: { status: "ok" }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error processing course events: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process events" }, status: :internal_server_error
    end
  end
end
