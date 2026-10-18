# frozen_string_literal: true

module Catalog
  # A single course section (one CRN) as the public catalog API returns it.
  class SectionSerializer
    # catalog_courses: the CatalogCourse rows of a list of sections, from
    # CourseQuery.for_sections, so a list sends one query. Without it, the
    # serializer looks the one course up.
    def initialize(course, catalog_courses: nil)
      @course = course
      @catalog_courses = catalog_courses
    end

    def as_json(*)
      return nil if @course.nil?

      {
        crn:                @course.crn,
        pub_id:             @course.public_id,
        term:               term,
        subject:            @course.subject,
        subject_code:       @course.prefix,
        course_number:      @course.course_number,
        section_number:     @course.section_number,
        course_code:        course_code,
        title:              @course.title,
        schedule_type:      @course.schedule_type,
        schedule_type_code: Course::ScheduleType.new(@course.schedule_type).code,
        credit_hours:       @course.credit_hours,
        grade_mode:         @course.grade_mode,
        status:             @course.status,
        seats:              seats,
        linked:             linked,
        start_date:         @course.start_date,
        end_date:           @course.end_date,
        instructors:        @course.faculties.map { |f| InstructorSerializer.new(f).as_json },
        meeting_times:      meeting_times,
        final_exam:         final_exam,
        course:             course_details
      }
    end

    def self.course_code_for(course)
      "#{course.prefix} #{course.course_number}-#{course.section_number}"
    end

    private

    def course_code
      self.class.course_code_for(@course)
    end

    # What Banner says about the course: the description, the prerequisites,
    # and the terms it is usually offered. GET /api/v1/catalog/courses/:code
    # has the full record. Nil until Catalog::CourseDetailsSync stores it.
    def course_details
      catalog_course =
        if @catalog_courses
          @catalog_courses[[ @course.prefix, @course.course_number ]]
        else
          CatalogCourse.find_by(subject_code: @course.prefix, course_number: @course.course_number)
        end
      return nil if catalog_course.nil?

      {
        code:              catalog_course.code,
        description:       catalog_course.description,
        prerequisites:     catalog_course.prerequisites,
        typically_offered: catalog_course.typically_offered
      }
    end

    def term
      { uid: @course.term.uid, name: @course.term.name }
    end

    # Live enrollment numbers from Banner, by way of Catalog::LeopardWebClient. The
    # catalog import sets them, and Catalog::CourseDataSyncJob refreshes them every night.
    # They are therefore up to a day old. Do not present them as a real-time
    # seat count. Null when Banner did not return enrollment data for the CRN.
    def seats
      { capacity: @course.seats_capacity, available: @course.seats_available }
    end

    # Banner marks the sections a student has to register together, most often a
    # lecture and its lab. Catalog::SectionLinks gives Banner's own pairs once
    # they are fetched, and says which source it used.
    def linked
      SectionLinks.new(@course).as_json
    end

    def meeting_times
      @course.filtered_meeting_times
             .sort_by { |mt| [ Course::MeetingTime.day_of_weeks[mt.day_of_week], mt.begin_time ] }
             .map { |mt| MeetingTimeSerializer.new(mt).as_json }
    end

    def final_exam
      exam = @course.final_exam
      return nil if exam.nil?

      {
        date:       exam.exam_date,
        start_time: exam.formatted_start_time,
        end_time:   exam.formatted_end_time,
        location:   exam.location
      }
    end
  end
end
