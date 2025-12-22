# frozen_string_literal: true

module Api
  class CoursesController < ApiController
    # POST /api/process_courses
    # Initial course processing - creates enrollments and calendar events
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

    # POST /api/courses/reprocess
    # Reprocesses courses for a term - removes old enrollments, adds new ones
    # Used when a user changes their schedule in LeopardWeb
    def reprocess
      courses = params[:courses] || params[:_json]

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      # Convert ActionController::Parameters to plain hashes
      courses_array = courses.map do |course|
        course.is_a?(ActionController::Parameters) ? course.to_unsafe_h : course.to_h
      end

      # Reprocess courses - removes old enrollments, adds new ones
      result = CourseReprocessService.new(courses_array, current_user).call

      ics_url = current_user.cal_url_with_extension

      render json: {
        ics_url: ics_url,
        removed_enrollments: result[:removed_enrollments],
        removed_courses: result[:removed_courses],
        processed_courses: result[:processed_courses]
      }, status: :ok

    rescue ArgumentError => e
      Rails.logger.error("Invalid reprocess request: #{e.message}")
      render json: { error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error("Error reprocessing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to reprocess courses" }, status: :internal_server_error
    end

  end
end
