# frozen_string_literal: true

module Catalog
  # The rules for sections that a student takes together in one term, and the
  # totals of a set of sections. Catalog::ScheduleCheck reports where a set of
  # sections breaks them. Catalog::ScheduleOptions builds only schedules that
  # keep them. Change a rule here, and both change.
  #
  # The rules:
  # - A conflict: two meetings on the same day, at overlapping times, during
  #   overlapping dates (overlap?). Half-term sections in different halves do
  #   not conflict.
  # - A linked section needs every section of one of its option groups
  #   (Catalog::SectionLinks#met_by?).
  # - A duplicate: the same subject, number, and schedule type twice
  #   (duplicate_key). A lecture and its lab are not duplicates.
  # - A cancelled section is never part of a schedule.
  module ScheduleRules
    EARLY_START = 900 # HHMM: a meeting that starts before 9:00

    DAYS = Course::MeetingTime.day_of_weeks.keys.freeze

    module_function

    # The meetings that take up time in a week. An all-day meeting and a
    # meeting with no time (online, arranged) take up none.
    def meetings(course)
      course.filtered_meeting_times.reject(&:all_day?).select { |mt| mt.begin_time.present? && mt.end_time.present? }
    end

    # x and y respond to day_of_week, begin_time, end_time, start_date, and
    # end_date: a Course::MeetingTime or a Catalog::ScheduleOptions::Slot.
    # Meetings that only touch (one ends at 11:15, one starts at 11:15) do not
    # conflict.
    def overlap?(x, y)
      x.day_of_week == y.day_of_week &&
        x.begin_time < y.end_time && y.begin_time < x.end_time &&
        dates_overlap?(x, y)
    end

    # A meeting with no dates overlaps every other meeting.
    def dates_overlap?(x, y)
      return true if [ x.start_date, x.end_date, y.start_date, y.end_date ].any?(&:nil?)

      x.start_date <= y.end_date && y.start_date <= x.end_date
    end

    def duplicate_key(course)
      [ course.subject, course.course_number, course.schedule_type ]
    end

    # Credit hours, days, earliest start, latest end, and meetings before 9:00.
    def totals(sections)
      all = sections.flat_map { |course| meetings(course) }
      used_days = DAYS.select { |day| all.any? { |mt| mt.day_of_week == day } }

      {
        credit_hours:         credit_hours(sections),
        days:                 used_days,
        earliest_start:       all.min_by(&:begin_time)&.fmt_begin_time_military,
        latest_end:           all.max_by(&:end_time)&.fmt_end_time_military,
        meetings_before_nine: all.count { |mt| mt.begin_time < EARLY_START }
      }
    end

    # Banner's pairs carry each partner's credits as Banner counts them in the
    # pair, 0 for a lab. A section uses those credits when another chosen
    # section's pair names it. Otherwise it uses its own credit hours. A
    # course (subject and number) with no Banner credits counts once, at the
    # highest credit hours among its chosen sections, because older rows can
    # still give a lab the lecture's credits.
    def credit_hours(sections)
      banner = sections.flat_map(&:section_links)
                       .reject { |link| link.credit_hours.nil? }
                       .to_h { |link| [ link.linked_course_id, link.credit_hours ] }

      sections.group_by { |course| [ course.subject, course.course_number ] }.sum do |_key, group|
        credits = group.map { |course| banner[course.id] }
        if credits.any?
          group.zip(credits).sum { |course, hours| (hours || course.credit_hours).to_i }
        else
          group.filter_map(&:credit_hours).max.to_i
        end
      end
    end
  end
end
