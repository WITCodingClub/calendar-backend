# frozen_string_literal: true

module Catalog
  # A single course section (one CRN) as the public catalog API returns it.
  class SectionSerializer
    # A list of sections, with their catalog courses loaded in one query.
    def self.collection(sections)
      sections = sections.to_a
      catalog_courses = CatalogCourse.for_sections(sections)
      sections.map { |section| new(section, catalog_courses: catalog_courses).as_json }
    end

    # catalog_courses: the CatalogCourse rows of a list of sections, from
    # CatalogCourse.for_sections. Without it, the serializer looks the one
    # course up.
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
        course_code:        Fields.section_code(@course),
        title:              @course.title,
        schedule_type:      @course.schedule_type,
        schedule_type_code: Course::ScheduleType.new(@course.schedule_type).code,
        credit_hours:       @course.credit_hours,
        grade_mode:         @course.grade_mode,
        status:             @course.status,
        seats:              seats,
        waitlist:           waitlist,
        linked:             linked,
        cross_list:         Fields.cross_list(@course),
        part_of_term:       @course.part_of_term,
        campus:             @course.campus,
        start_date:         @course.start_date,
        end_date:           @course.end_date,
        instructors:        @course.faculties.map { |f| InstructorSerializer.new(f).as_json },
        meeting_times:      meeting_times,
        final_exam:         final_exam,
        course:             course_details
      }
    end

    private

    # What Banner says about the course: the description, the prerequisites,
    # and the terms it is usually offered. GET /api/v1/catalog/courses/:code
    # has the full record. Nil until Catalog::CourseDetailsSync stores it.
    def course_details
      catalog_course =
        if @catalog_courses
          @catalog_courses[[ @course.prefix, @course.course_number ]]
        else
          @course.catalog_course
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

    # Enrollment numbers from Banner. The catalog import sets them, and
    # Catalog::CourseDataSyncJob and Catalog::SeatRefreshJob refresh them
    # (Catalog::Freshness). Do not present them as a real-time seat count. Null when Banner did not return
    # enrollment data for the CRN.
    def seats
      { capacity: @course.seats_capacity, available: @course.seats_available }
    end

    # The waitlist counts, from the same Banner data and jobs as seats.
    def waitlist
      { capacity: @course.waitlist_capacity, available: @course.waitlist_available }
    end

    # Banner marks the sections a student has to register together, most often a
    # lecture and its lab. Catalog::SectionLinks gives Banner's own pairs once
    # they are fetched, and says which source it used.
    def linked
      SectionLinks.new(@course).as_json
    end

    def meeting_times
      Fields.meeting_times(@course).map { |mt| MeetingTimeSerializer.new(mt).as_json }
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
