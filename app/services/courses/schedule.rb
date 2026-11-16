# frozen_string_literal: true

module Courses
  # One user's schedule for the dashboard/schedules/_calendar partial: the
  # signed-in user's own schedule, or a friend's.
  Schedule = Data.define(
    :terms, :selected_term, :view_mode, :today, :week_start, :month_date,
    :courses, :schedule_by_day, :no_class_dates
  )

  class Schedule
    WEEKDAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

    # term_uid, week_start ("2026-09-14"), month ("2026-09") and view come from
    # the page's query string. A missing or bad value falls back to the
    # current term, this week, or this month.
    def self.build(user, term_uid: nil, week_start: nil, month: nil, view: nil)
      current_term  = Term.current
      terms         = terms_for(user, current_term)
      selected_term = term_uid.present? ? terms.find_by(uid: term_uid) : terms.find_by(id: current_term&.id) || terms.first
      today         = Time.zone.today
      week_start    = week_start_for(week_start, today)
      month_date    = parse_date("#{month}-01")&.beginning_of_month || today.beginning_of_month
      courses       = selected_term ? EnrolledCourses.for(user, selected_term).map(&:with_indifferent_access) : []

      new(
        terms:           terms,
        selected_term:   selected_term,
        # With no view in the URL, the partial shows the list on a small
        # screen and the week grid on a larger one.
        view_mode:       view.presence_in(%w[list week month]) || "auto",
        today:           today,
        week_start:      week_start,
        month_date:      month_date,
        courses:         courses,
        schedule_by_day: by_day(courses),
        no_class_dates:  UniversityCalendarEvent.no_class_dates_between(
          [ week_start, month_date ].min, [ week_start + 6, month_date.end_of_month ].max
        )
      )
    end

    # The terms the schedule page lists for a user: the enrolled current and
    # future terms, or the last 6 enrolled terms when there are none. The MCP
    # my_courses tool links to the page only for these terms.
    def self.terms_for(user, current_term = Term.current)
      enrolled_terms = Term.enrolled_for(user)
      terms = enrolled_terms.current_and_future(current_term)
      terms.empty? ? enrolled_terms.reverse_chronological.limit(6) : terms
    end

    # The Monday of the week of +value+, or of the week of +today+ when the
    # value is not a date.
    def self.week_start_for(value, today = Time.zone.today)
      (parse_date(value) || today).beginning_of_week(:monday)
    end

    def self.parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def self.by_day(courses)
      by_day = Hash.new { |hash, day| hash[day] = [] }
      courses.each do |course|
        Array(course[:meeting_times]).each do |meeting_time|
          WEEKDAYS.each { |day| by_day[day] << { course: course, meeting_time: meeting_time } if meeting_time[day] }
        end
      end
      by_day
    end
    private_class_method :parse_date, :by_day
  end
end
