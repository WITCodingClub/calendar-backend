# frozen_string_literal: true

require "csv"

# Public read-only CSV exports for BI tools (Power BI Web connector, Excel).
# Course schedule data only — never expose user data through these reports.
#
# Inherits ActionController::Base, not ApplicationController: consumers are
# data tools (Power BI, curl), so the allow_browser check must not run here.
class ReportsController < ActionController::Base
  MEETING_TIMES_HEADERS = %w[
    term_uid term crn subject course_number section_number title
    schedule_type status seats_capacity seats_available
    day day_of_week begin_time end_time meeting_type
  ].freeze

  def meeting_times
    scope = Course::MeetingTime.joins(course: :term)
    scope = scope.where(terms: { uid: params[:term_uid] }) if params[:term_uid].present?

    # DISTINCT: a concurrent-ingest race can leave identical meeting time rows
    # (e.g. CRN 17294 in 202710 has 5 copies); the feed must not repeat them.
    rows = scope
           .distinct
           .order(Arel.sql("terms.uid, courses.crn, course_meeting_times.day_of_week, course_meeting_times.begin_time"))
           .pluck(
             "terms.uid", "terms.season", "terms.year",
             "courses.crn", "courses.subject", "courses.course_number",
             "courses.section_number", "courses.title", "courses.schedule_type",
             "courses.status", "courses.seats_capacity", "courses.seats_available",
             "course_meeting_times.day_of_week",
             "course_meeting_times.begin_time", "course_meeting_times.end_time",
             "course_meeting_times.meeting_schedule_type"
           )

    expires_in 1.hour, public: true
    send_data build_meeting_times_csv(rows), type: "text/csv; charset=utf-8",
                                             filename: "meeting_times.csv", disposition: "inline"
  end

  private

  def build_meeting_times_csv(rows)
    CSV.generate do |csv|
      csv << MEETING_TIMES_HEADERS

      rows.each do |uid, season, year, crn, subject, course_number, section_number, title,
                    schedule_type, status, seats_capacity, seats_available,
                    day_of_week, begin_time, end_time, meeting_schedule_type|
        # pluck type-casts enum columns, so season/day_of_week/meeting_schedule_type
        # arrive as their string keys ("fall", "monday", "lecture")
        csv << [
          uid, "#{season.capitalize} #{year}",
          crn, subject, course_number, section_number, title,
          schedule_type, status, seats_capacity, seats_available,
          day_of_week, Course::MeetingTime.day_of_weeks.fetch(day_of_week),
          format_hhmm(begin_time), format_hhmm(end_time),
          meeting_schedule_type
        ]
      end
    end
  end

  # begin_time/end_time are stored as HHMM integers (e.g. 1350 => "13:50")
  def format_hhmm(hhmm)
    format("%02d:%02d", hhmm / 100, hhmm % 100)
  end
end
