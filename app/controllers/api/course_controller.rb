module Api
  class CourseController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token

    def process_courses
      courses = params[:courses] || params[:_json]

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      # Process courses using the service with the current user
      processed_data = CourseProcessorService.new(courses, current_user).call

      # remove all id fields from processed_data for security
      processed_data.each do |course|
        course.delete(:id)
        course[:term].delete(:id) if course[:term]
      end

      render json: { classes: processed_data }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process courses" }, status: :internal_server_error
    end
  end
end
