# frozen_string_literal: true

module Api
  class CoursesController < BaseController
    authenticate_with_token

    def process_courses
      skip_authorization

      Courses::Processor.new(courses_payload, current_user).call

      render json: {
        user_pub: current_user.public_id,
        ics_url:  current_user.cal_url_with_extension
      }, status: :ok
    end

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

    def reprocess
      skip_authorization

      result = Courses::Reprocessor.new(courses_payload, current_user).call

      render json: {
        ics_url:             current_user.cal_url_with_extension,
        removed_enrollments: result[:removed_enrollments],
        removed_courses:     result[:removed_courses],
        processed_courses:   result[:processed_courses]
      }, status: :ok
    end

    private

    # The course list of POST /api/process_courses and /api/reprocess, as plain
    # hashes: a "courses" key, or a bare JSON array.
    def courses_payload
      courses = params[:courses] || params[:_json]
      raise ActionController::BadRequest, "No courses provided" if courses.blank?

      courses.map do |course|
        course.is_a?(ActionController::Parameters) ? course.to_unsafe_h : course.to_h
      end
    end
  end
end
