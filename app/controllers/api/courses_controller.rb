# frozen_string_literal: true

module Api
  class CoursesController < BaseController
    authenticate_with_token

    # POST /api/process_courses
    def process_courses
      skip_authorization

      courses = params[:courses] || params[:_json]

      if courses.blank?
        render_error "No courses provided", status: :bad_request
        return
      end

      courses_array = plain_hashes(courses)

      Courses::Processor.new(courses_array, current_user).call

      render json: {
        user_pub: current_user.public_id,
        ics_url:  current_user.cal_url_with_extension
      }, status: :ok
    rescue => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render_error "Failed to process courses", status: :internal_server_error
    end

    # POST /api/process_courses/batch
    #
    # Body: { "terms": [ { "term": "202710", "courses": [ ... ] }, ... ] }
    # Each "courses" array has the same shape as the body of
    # POST /api/process_courses. The first term is processed now. The other
    # terms go to a background job and come back as "pending".
    def process_courses_batch
      skip_authorization

      terms = params[:terms]

      unless terms.is_a?(Array) && terms.any?
        render_error "No terms provided", status: :bad_request
        return
      end

      if terms.size > Courses::BatchProcessor::MAX_TERMS
        render_error "A batch can have at most #{Courses::BatchProcessor::MAX_TERMS} terms", status: :bad_request
        return
      end

      entries = terms.map do |entry|
        entry.is_a?(ActionController::Parameters) ? entry.to_unsafe_h : entry
      end

      results = Courses::BatchProcessor.new(entries, current_user).call

      render json: CourseBatchResultSerializer.new(current_user, results).as_json, status: :ok
    end

    # POST /api/courses/reprocess
    def reprocess
      skip_authorization

      courses = params[:courses] || params[:_json]

      if courses.blank?
        render_error "No courses provided", status: :bad_request
        return
      end

      courses_array = plain_hashes(courses)

      result = Courses::Reprocessor.new(courses_array, current_user).call

      render json: {
        ics_url:             current_user.cal_url_with_extension,
        removed_enrollments: result[:removed_enrollments],
        removed_courses:     result[:removed_courses],
        processed_courses:   result[:processed_courses]
      }, status: :ok
    rescue ArgumentError => e
      render_error e.message, status: :bad_request
    rescue => e
      Rails.logger.error("Error reprocessing courses: #{e.message}")
      render_error "Failed to reprocess courses", status: :internal_server_error
    end

    private

    def plain_hashes(courses)
      courses.map do |course|
        course.is_a?(ActionController::Parameters) ? course.to_unsafe_h : course.to_h
      end
    end
  end
end
