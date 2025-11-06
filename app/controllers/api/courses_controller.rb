# frozen_string_literal: true

module Api
  class CoursesController < ApiController
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
      ics_url = current_user.cal_url_with_extension


      render json: {
        ics_url: ics_url,
        classes: processed_data
      }, status: :ok
    rescue => e
      Rails.logger.error("Error processing courses: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to process courses" }, status: :internal_server_error
    end

    private

    def group_meeting_times(meeting_times)
      # Group meeting times by their common attributes (time, date range, location)
      grouped = meeting_times.group_by do |mt|
        [mt.begin_time, mt.end_time, mt.start_date, mt.end_date, mt.room_id]
      end

      # Convert each group into a single meeting time object with day flags
      grouped.map do |_key, mts|
        # Use the first meeting time as the base
        mt = mts.first

        # Initialize all days to false
        days = {
          monday: false,
          tuesday: false,
          wednesday: false,
          thursday: false,
          friday: false,
          saturday: false,
          sunday: false
        }

        # Set true for each day that appears in the group
        mts.each do |meeting_time|
          day_symbol = meeting_time.day_of_week&.to_sym
          days[day_symbol] = true if day_symbol
        end

        {
          begin_time: mt.fmt_begin_time,
          end_time: mt.fmt_end_time,
          start_date: mt.start_date,
          end_date: mt.end_date,
          location: {
            building: if mt.building
                        {
                          name: mt.building.name,
                          abbreviation: mt.building.abbreviation
                        }
                      else
                        nil
                      end,
            room: mt.room&.formatted_number
          },
          **days
        }
      end
    end

    def fetch_processed_courses(courses, user)
      # Deduplicate courses by CRN and term
      unique_courses = courses.uniq { |c| [c[:crn] || c["crn"], c[:term] || c["term"]] }

      # Collect all CRNs and convert to integers
      crns = unique_courses.map { |c| (c[:crn] || c["crn"]).to_i }.compact

      # Eager load associations to avoid N+1 queries
      courses_by_crn = Course.where(crn: crns)
                             .includes(:term, :faculties, meeting_times: [:room, :building])
                             .index_by(&:crn)


      unique_courses.map do |course_data|
        crn = (course_data[:crn] || course_data["crn"]).to_i
        course = courses_by_crn[crn]

        unless course
          Rails.logger.warn "Course not found for CRN: #{crn}"
          next
        end

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
            email: course.faculties[0]&.email,
            rmp_id: course.faculties[0]&.rmp_id
          },
          meeting_times: group_meeting_times(course.meeting_times)
        }
      end.compact


    end

  end
end
