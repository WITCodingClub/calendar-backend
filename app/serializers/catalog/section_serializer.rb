# frozen_string_literal: true

module Catalog
  # A single course section (one CRN) as the public catalog API returns it.
  class SectionSerializer
    def initialize(course)
      @course = course
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
        final_exam:         final_exam
      }
    end

    def self.course_code_for(course)
      "#{course.prefix} #{course.course_number}-#{course.section_number}"
    end

    private

    def course_code
      self.class.course_code_for(@course)
    end

    def term
      { uid: @course.term.uid, name: @course.term.name }
    end

    # Live enrollment numbers from Banner, by way of LeopardWebService. The
    # catalog import sets them, and CourseDataSyncJob refreshes them every night.
    # They are therefore up to a day old. Do not present them as a real-time
    # seat count. Null when Banner did not return enrollment data for the CRN.
    def seats
      { capacity: @course.seats_capacity, available: @course.seats_available }
    end

    # Banner marks the sections a student has to register together, most often a
    # lecture and its lab. `crns` names the partners in the same term, so a
    # client does not have to guess the pairing from the section number.
    def linked
      partners = @course.linked_sections.pluck(:crn, :id)

      {
        required:   @course.is_section_linked,
        identifier: @course.link_identifier,
        crns:       partners.map(&:first),
        pub_ids:    partners.map { |(_crn, id)| Course.public_id_for(id) }
      }
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
