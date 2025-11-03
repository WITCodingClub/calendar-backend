module Api
  class CoursesController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token

    def process_courses
      courses = params[:courses] || params[:_json]

      Rails.logger.debug "=== COURSES API CALLED ==="
      Rails.logger.debug "Raw params: #{params.inspect}"
      Rails.logger.debug "Courses param: #{courses.inspect}"

      if courses.blank?
        render json: { error: "No courses provided" }, status: :bad_request
        return
      end

      # Process courses synchronously
      Rails.logger.debug "Processing #{courses.size} courses for user #{current_user.id}"
      CourseProcessorJob.perform_now(courses, current_user.id)
      Rails.logger.debug "Course processing completed"

      # Fetch the processed data to return to a client
      processed_data = fetch_processed_courses(courses, current_user)
      ics_url = current_user.cal_url_with_extension


      render json: {
        ics_url: ics_url,
        classes: processed_data
      }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process courses" }, status: :internal_server_error
    end

    private

    def fetch_processed_courses(courses, user)
      # Deduplicate courses by CRN and term
      unique_courses = courses.uniq { |c| [c[:crn] || c['crn'], c[:term] || c['term']] }

      # Collect all CRNs and convert to integers
      crns = unique_courses.map { |c| (c[:crn] || c['crn']).to_i }.compact

      Rails.logger.debug "Looking for courses with CRNs: #{crns.inspect}"

      # Eager load associations to avoid N+1 queries
      courses_by_crn = Course.where(crn: crns)
                             .includes(:term, :faculties, meeting_times: [:room, :building])
                             .index_by(&:crn)

      Rails.logger.debug "Found #{courses_by_crn.size} courses in database"
      Rails.logger.debug "Course CRNs found: #{courses_by_crn.keys.inspect}"

      processed_data = unique_courses.map do |course_data|
        crn = (course_data[:crn] || course_data['crn']).to_i
        Rails.logger.debug "Processing course with CRN: #{crn} (#{crn.class})"
        course = courses_by_crn[crn]

        unless course
          Rails.logger.warn "Course not found for CRN: #{crn}"
          next
        end

        Rails.logger.debug "Found course: #{course.title}"
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
          professor: {
            first_name: course.faculties[0]&.first_name,
            last_name: course.faculties[0]&.last_name,
            email: course.faculties[0]&.email
          },
          meeting_times: course.meeting_times.map do |mt|
            {
              begin_time: mt.fmt_begin_time,
              end_time: mt.fmt_end_time,
              start_date: mt.start_date,
              end_date: mt.end_date,
              location: {
                building: mt.building ? {
                  name: mt.building.name,
                  abbreviation: mt.building.abbreviation
                } : nil,
                room: mt.room&.formatted_number
              },
              monday: mt.monday?,
              tuesday: mt.tuesday?,
              wednesday: mt.wednesday?,
              thursday: mt.thursday?,
              friday: mt.friday?,
              saturday: mt.saturday?,
              sunday: mt.sunday?
            }
          end
        }
      end.compact

      Rails.logger.debug "Processed #{processed_data.size} courses for response"
      processed_data
    end
  end
end
