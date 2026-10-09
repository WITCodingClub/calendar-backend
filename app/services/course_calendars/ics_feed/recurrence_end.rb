# frozen_string_literal: true

module CourseCalendars
  class IcsFeed
    # The last day of the weekly rule of a class. Classes stop the day before
    # the course's own final, else the day before the first final of the term,
    # and always before the finals period or study day of the term.
    #
    # Each lookup runs once and is kept for the rest of the feed.
    class RecurrenceEnd
      def initialize(courses)
        @courses             = courses
        @term_finals         = {}
        @term_finals_periods = {}
      end

      def for(meeting_time, course)
        recurrence_end = meeting_time.end_date.to_date

        course_final = final_exam_date_for_course(course.id)
        if course_final && course_final < recurrence_end
          recurrence_end = course_final - 1.day
        else
          term_finals_start = earliest_final_for_term(course.term_id)
          if term_finals_start && term_finals_start < recurrence_end
            recurrence_end = term_finals_start - 1.day
          end
        end

        study_day = earliest_finals_period_for_term(course.term_id)
        if study_day && (study_day - 1.day) < recurrence_end
          recurrence_end = study_day - 1.day
        end

        recurrence_end
      end

      private

      # The earliest final for each course, found with one grouped query for the
      # whole calendar instead of one query per course. A course with no final is
      # absent from the hash, so it reads as nil, as the per-course query did.
      def final_exam_date_for_course(course_id)
        @course_finals ||= FinalExam.where(course_id: @courses.map(&:id))
                                    .where.not(exam_date: nil)
                                    .group(:course_id)
                                    .minimum(:exam_date)
        @course_finals[course_id]
      end

      def earliest_final_for_term(term_id)
        return @term_finals[term_id] if @term_finals.key?(term_id)

        @term_finals[term_id] = FinalExam.where(term_id: term_id)
                                         .where.not(exam_date: nil)
                                         .minimum(:exam_date)
      end

      def earliest_finals_period_for_term(term_id)
        return @term_finals_periods[term_id] if @term_finals_periods.key?(term_id)

        @term_finals_periods[term_id] = UniversityCalendarEvent
                                        .where(term_id: term_id, category: "finals")
                                        .where("summary ILIKE ? OR summary ILIKE ?", "%Final Exam Period%", "%Study Day%")
                                        .minimum(:start_time)
                                        &.to_date
      end
    end
  end
end
