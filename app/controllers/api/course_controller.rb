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

      # Enqueue job to process courses
      job = CourseProcessorJob.perform_later(courses, current_user.id)

      render json: {
        message: "Course processing job enqueued",
        job_id: job.job_id
      }, status: :accepted
    rescue StandardError => e
      Rails.logger.error("Error enqueuing course processing job: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to enqueue course processing job" }, status: :internal_server_error
    end
  end
end
