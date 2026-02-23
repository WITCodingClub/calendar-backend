# frozen_string_literal: true

module Api
  class CoursesController < ApiController
    # POST /api/process_courses
    # Initial course processing - creates enrollments and calendar events
    def process_courses
      skip_authorization # User-self-service: always operates on current_user only
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
        user_pub: current_user.public_id,
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
      skip_authorization # User-self-service: always operates on current_user only
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

    # GET /api/courses/:id/prerequisites
    # Returns all prerequisites for a given course.
    def prerequisites
      @course = find_by_any_id!(Course, params[:id])
      authorize @course, :show?

      prereqs = @course.course_prerequisites.map do |p|
        {
          type: p.prerequisite_type,
          rule: p.prerequisite_rule,
          min_grade: p.min_grade,
          waivable: p.waivable
        }
      end

      render json: { prerequisites: prereqs }, status: :ok
    end

    # POST /api/courses/:id/check_eligibility
    # Checks whether the current user meets the prerequisites for a course.
    def check_eligibility
      @course = find_by_any_id!(Course, params[:id])
      authorize @course, :show?

      result = PrerequisiteValidationService.call(user: current_user, course: @course)

      render json: result, status: :ok
    end

  end
end
