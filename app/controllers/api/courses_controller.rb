# frozen_string_literal: true

module Api
  class CoursesController < ApiController
    # POST /api/process_courses
    def process_courses
      skip_authorization

      courses = params[:courses] || params[:_json]

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      courses_array = courses.map do |course|
        course.is_a?(ActionController::Parameters) ? course.to_unsafe_h : course.to_h
      end

      CourseProcessorService.new(courses_array, current_user).call

      render json: {
        user_pub: current_user.public_id,
        ics_url:  current_user.cal_url_with_extension
      }, status: :ok
    rescue => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process courses" }, status: :internal_server_error
    end

    # POST /api/courses/reprocess
    def reprocess
      skip_authorization

      courses = params[:courses] || params[:_json]

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      courses_array = courses.map do |course|
        course.is_a?(ActionController::Parameters) ? course.to_unsafe_h : course.to_h
      end

      result = CourseReprocessService.new(courses_array, current_user).call

      render json: {
        ics_url:             current_user.cal_url_with_extension,
        removed_enrollments: result[:removed_enrollments],
        removed_courses:     result[:removed_courses],
        processed_courses:   result[:processed_courses]
      }, status: :ok
    rescue ArgumentError => e
      render json: { error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error("Error reprocessing courses: #{e.message}")
      render json: { error: "Failed to reprocess courses" }, status: :internal_server_error
    end
  end
end
