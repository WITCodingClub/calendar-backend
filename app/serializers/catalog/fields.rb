# frozen_string_literal: true

module Catalog
  # The values of the catalog that take more than one column to compute. The
  # REST serializers and the GraphQL types both read them here, so the two
  # surfaces give the same answer and neither reaches into the other.
  module Fields
    # Where the review text comes from, for credit and for a link back.
    REVIEW_SOURCE = "ratemyprofessors.com"

    module_function

    # "COMP 2000-01".
    def section_code(course)
      "#{CourseCode.format(course.prefix, course.course_number)}-#{course.section_number}"
    end

    # Sections of other courses that meet with this one, such as an
    # undergraduate and a graduate studio. The seats count the whole group.
    # Nil when the section is not cross-listed.
    def cross_list(course)
      return nil if course.cross_list_identifier.nil?

      {
        identifier: course.cross_list_identifier,
        crns:       course.cross_listed_crns,
        seats:      { capacity: course.cross_list_capacity, available: course.cross_list_available }
      }
    end

    # The meeting rows by day, then by start. filtered_meeting_times drops the
    # duplicate rows a concurrent ingest can leave behind.
    def meeting_times(course)
      course.filtered_meeting_times.sort_by { |mt| [ Course::MeetingTime.day_of_weeks[mt.day_of_week], mt.begin_time ] }
    end

    # begin_time and end_time are HHMM integers, so plain subtraction would
    # make 09:45 to 10:00 look like 55 minutes.
    def duration_minutes(meeting_time)
      minutes(meeting_time.end_time) - minutes(meeting_time.begin_time)
    end

    def minutes(hhmm) = ((hhmm / 100) * 60) + (hhmm % 100)

    # Rate My Professors joins the tags of one review with "--".
    def review_tags(rating)
      rating.rating_tags.to_s.split("--").map(&:strip).reject(&:empty?)
    end

    # Rate My Professors reports "no data" as sentinel numbers: 0 for an
    # average with no ratings behind it, -1 for an unknown would-take-again
    # percentage. Those must not leave as if they were real scores.
    def rmp(faculty)
      stats = faculty.rmp_stats
      return nil if stats.nil? || stats[:num_ratings].to_i.zero?

      would_take_again = stats[:would_take_again_percent]
      {
        id:                       faculty.rmp_id,
        avg_rating:               stats[:avg_rating],
        avg_difficulty:           stats[:avg_difficulty],
        num_ratings:              stats[:num_ratings],
        would_take_again_percent: (would_take_again if would_take_again.to_f >= 0)
      }
    end
  end
end
