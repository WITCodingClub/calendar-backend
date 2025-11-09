# frozen_string_literal: true

module Api
  class CoursesController < ApiController
    def process_courses
      courses = params[:courses] || params[:_json]

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      # Convert ActionController::Parameters to plain hashes
      courses_array = courses.map do |course|
        course.is_a?(ActionController::Parameters) ? course.to_unsafe_h : course.to_h
      end

      # Process courses synchronously
      CourseProcessorJob.perform_now(courses_array, current_user.id)

      ics_url = current_user.cal_url_with_extension

      render json: {
        ics_url: ics_url,
      }, status: :ok

    rescue => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process courses" }, status: :internal_server_error
    end

  end
end
