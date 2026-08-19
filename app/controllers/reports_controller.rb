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
    schedule_type status credit_hours faculty
    seats_capacity seats_available enrollment_current
    day day_of_week begin_time end_time meeting_type
    building building_name room_number room room_capacity
  ].freeze

  TERMS_HEADERS = %w[term_uid term season year start_date end_date meeting_times].freeze

  # A course can be team-taught, so faculty is aggregated to one string here
  # rather than joined. Joining would multiply the rows and change the grain
  # of the feed from meeting-time-by-room to meeting-time-by-room-by-teacher.
  FACULTY_NAMES_SQL = <<~SQL.squish
    (SELECT STRING_AGG(
              COALESCE(faculties.display_name, faculties.first_name || ' ' || faculties.last_name),
              ', ' ORDER BY faculties.last_name, faculties.first_name)
       FROM courses_faculties
       JOIN faculties ON faculties.id = courses_faculties.faculty_id
      WHERE courses_faculties.course_id = courses.id)
  SQL

  def meeting_times
    scope = Course::MeetingTime.joins(course: :term)
    scope = scope.where(terms: { uid: params[:term_uid] }) if params[:term_uid].present?

    # LEFT JOIN: a meeting time with no room assigned (online, TBD) must still
    # appear. A meeting time booked into two rooms yields one row per room, so
    # the grain of this feed is meeting-time-by-room, not meeting-time.
    scope = scope.left_joins(meeting_time_rooms: { room: :building })

    # DISTINCT: a concurrent-ingest race can leave identical meeting time rows
    # (e.g. CRN 17294 in 202710 has 5 copies); the feed must not repeat them.
    rows = scope
           .distinct
           .order(Arel.sql("terms.uid, courses.crn, course_meeting_times.day_of_week, " \
                           "course_meeting_times.begin_time, buildings.abbreviation, rooms.number"))
           .pluck(
             "terms.uid", "terms.season", "terms.year",
             "courses.crn", "courses.subject", "courses.course_number",
             "courses.section_number", "courses.title", "courses.schedule_type",
             "courses.status", "courses.credit_hours", Arel.sql(FACULTY_NAMES_SQL),
             "courses.seats_capacity", "courses.seats_available",
             "course_meeting_times.day_of_week",
             "course_meeting_times.begin_time", "course_meeting_times.end_time",
             "course_meeting_times.meeting_schedule_type",
             "buildings.abbreviation", "buildings.name", "rooms.number",
             "rooms.capacity"
           )

    expires_in 1.hour, public: true
    send_data build_meeting_times_csv(rows), type: "text/csv; charset=utf-8",
                                             filename: "meeting_times.csv", disposition: "inline"
  end

  # Term list for tools that need to discover valid term_uid values.
  # Only terms with schedule data are listed, so every row here is a term the
  # meeting_times report can actually answer for.
  def terms
    # Subquery, not a join: the chronological scope orders by a CASE expression,
    # which Postgres rejects alongside SELECT DISTINCT.
    with_schedule = Course.where(id: Course::MeetingTime.select(:course_id)).select(:term_id)

    rows = Term
           .where(id: with_schedule)
           .chronological
           .pluck("terms.uid", "terms.season", "terms.year", "terms.start_date", "terms.end_date")

    counts = Course::MeetingTime.joins(course: :term).group("terms.uid").distinct.count

    csv = CSV.generate do |out|
      out << TERMS_HEADERS
      rows.each do |uid, season, year, start_date, end_date|
        out << [ uid, "#{season.capitalize} #{year}", season, year,
                 start_date, end_date, counts[uid] ]
      end
    end

    expires_in 1.hour, public: true
    send_data csv, type: "text/csv; charset=utf-8",
                   filename: "terms.csv", disposition: "inline"
  end

  private

  def build_meeting_times_csv(rows)
    CSV.generate do |csv|
      csv << MEETING_TIMES_HEADERS

      rows.each do |uid, season, year, crn, subject, course_number, section_number, title,
                    schedule_type, status, credit_hours, faculty,
                    seats_capacity, seats_available,
                    day_of_week, begin_time, end_time, meeting_schedule_type,
                    building_abbreviation, building_name, room_number, room_capacity|
        # pluck type-casts enum columns, so season/day_of_week/meeting_schedule_type
        # arrive as their string keys ("fall", "monday", "lecture")
        csv << [
          uid, "#{season.capitalize} #{year}",
          crn, subject, course_number, section_number, title,
          schedule_type, status, credit_hours, faculty,
          seats_capacity, seats_available, enrollment_current(seats_capacity, seats_available),
          day_of_week, Course::MeetingTime.day_of_weeks.fetch(day_of_week),
          format_hhmm(begin_time), format_hhmm(end_time),
          meeting_schedule_type,
          building_abbreviation, building_name, format_room_number(room_number),
          format_room(building_abbreviation, room_number), room_capacity
        ]
      end
    end
  end

  # Banner reports seats, not heads, so current enrollment is the difference.
  # Blank rather than a wrong 0 when either side is missing.
  def enrollment_current(seats_capacity, seats_available)
    return nil if seats_capacity.nil? || seats_available.nil?

    seats_capacity - seats_available
  end

  # begin_time/end_time are stored as HHMM integers (e.g. 1350 => "13:50")
  def format_hhmm(hhmm)
    format("%02d:%02d", hhmm / 100, hhmm % 100)
  end

  # Mirrors Room#formatted_number: pad purely numeric rooms to 3 digits so
  # "5" and "005" sort and group as one room in a BI tool.
  def format_room_number(number)
    return nil if number.blank?

    number.to_s.match?(/\A\d+\z/) ? number.to_s.rjust(3, "0") : number.to_s
  end

  # Single pre-joined label ("ANX 305") so a BI tool can group by room
  # without concatenating two columns itself.
  def format_room(building_abbreviation, number)
    return nil if building_abbreviation.blank?

    [ building_abbreviation, format_room_number(number) ].compact.join(" ")
  end
end
