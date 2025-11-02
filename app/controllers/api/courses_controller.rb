module Api
  class CoursesController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token

    def process_courses
      courses = params[:courses] || params[:_json]

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      # Process courses synchronously
      CourseProcessorJob.perform_now(courses, current_user.id)

      # Fetch the processed data to return to a client
      processed_data = fetch_processed_courses(courses, current_user)

      render json: { classes: processed_data }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process courses" }, status: :internal_server_error
    end

    private

    def fetch_processed_courses(courses, user)
      # Deduplicate courses by CRN and term
      unique_courses = courses.uniq { |c| [c[:crn] || c['crn'], c[:term] || c['term']] }

      processed_data = unique_courses.map do |course_data|
        crn = course_data[:crn] || course_data['crn']
        term_uid = course_data[:term] || course_data['term']

        course = Course.find_by(crn: crn)
        next unless course

        term = course.term

        {
          title: course.title,
          course_number: course.course_number,
          schedule_type: course.schedule_type,
          term: {
            uid: term.uid,
            season: term.season,
            year: term.year
          },
          meeting_times: course.meeting_times.map do |mt|
            {
              begin_time: mt.fmt_begin_time,
              end_time: mt.fmt_end_time,
              start_date: mt.start_date,
              end_date: mt.end_date,
              day_of_week: mt.day_of_week,
              location: {
                building: mt.building ? {
                  name: mt.building.name,
                  abbreviation: mt.building.abbreviation
                } : nil,
                room: mt.room&.formatted_number
              }
            }
          end
        }
      end.compact

      processed_data
    end
  end
end
