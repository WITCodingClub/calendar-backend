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

  SECTIONS_HEADERS = %w[
    term_uid term crn subject course_number section_number title
    schedule_type status credit_hours faculty
    seats_capacity seats_available enrollment_current
    meeting_days meeting_times meeting_type room room_capacity meeting_count
  ].freeze

  # Banner's single-letter day codes, so "MW" reads the way a schedule does.
  # R is Thursday and U is Sunday, because T and S are already taken.
  DAY_CODES = {
    "monday" => "M", "tuesday" => "T", "wednesday" => "W", "thursday" => "R",
    "friday" => "F", "saturday" => "S", "sunday" => "U"
  }.freeze

  # Separates one meeting pattern from the next inside a single cell. Faculty
  # names already use ", ", so a second separator keeps the two unambiguous.
  PATTERN_SEPARATOR = "; "

  # Offsets into a #meeting_time_rows tuple. #sections groups those tuples in
  # Ruby, so it reads single columns rather than destructuring the whole row.
  DAY_OF_WEEK_INDEX   = 14
  BEGIN_TIME_INDEX    = 15
  END_TIME_INDEX      = 16
  MEETING_TYPE_INDEX  = 17
  BUILDING_INDEX      = 18
  ROOM_NUMBER_INDEX   = 20
  ROOM_CAPACITY_INDEX = 21

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

  # One row per meeting time in one room. Use this grain for room and time
  # questions. For one row per section, use #sections instead.
  def meeting_times
    expires_in 1.hour, public: true
    send_data build_meeting_times_csv(meeting_time_rows),
              type: "text/csv; charset=utf-8",
              filename: "meeting_times.csv", disposition: "inline"
  end

  # One row per section, with the meeting days collapsed into a "MW" style
  # pattern. This is the grain most people expect: a section they take or
  # teach appears once. A section that meets twice a week reads as one course
  # here, where the meeting_times feed shows it as two rows.
  def sections
    expires_in 1.hour, public: true
    send_data build_sections_csv(meeting_time_rows),
              type: "text/csv; charset=utf-8",
              filename: "sections.csv", disposition: "inline"
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

  # The one query both CSV feeds read. Returns meeting-time-by-room tuples,
  # ordered so a section's meetings arrive together and in week order.
  def meeting_time_rows
    scope = Course::MeetingTime.joins(course: :term)
    scope = scope.where(terms: { uid: params[:term_uid] }) if params[:term_uid].present?

    # LEFT JOIN: a meeting time with no room assigned (online, TBD) must still
    # appear. A meeting time booked into two rooms yields one row per room, so
    # the grain of this query is meeting-time-by-room, not meeting-time.
    scope = scope.left_joins(meeting_time_rooms: { room: :building })

    # DISTINCT: a concurrent-ingest race can leave identical meeting time rows
    # (e.g. CRN 17294 in 202710 has 5 copies); the feeds must not repeat them.
    scope
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
  end

  def build_sections_csv(rows)
    CSV.generate do |csv|
      csv << SECTIONS_HEADERS

      # group_by keeps first-seen order, so the SQL ordering carries through.
      rows.group_by { |row| [ row[0], row[3] ] }.each_value do |section_rows|
        csv << section_row(section_rows)
      end
    end
  end

  # Collapses one section's meeting-time-by-room tuples into a single row.
  def section_row(rows)
    uid, season, year, crn, subject, course_number, section_number, title,
      schedule_type, status, credit_hours, faculty,
      seats_capacity, seats_available = rows.first

    patterns = meeting_patterns(rows)

    [
      uid, "#{season.capitalize} #{year}",
      crn, subject, course_number, section_number, title,
      schedule_type, status, credit_hours, faculty,
      seats_capacity, seats_available, enrollment_current(seats_capacity, seats_available),
      join_patterns(patterns.map { |p| p[:days] }),
      join_patterns(patterns.map { |p| p[:time] }),
      join_patterns(patterns.map { |p| p[:meeting_type] }),
      join_patterns(patterns.map { |p| p[:room] }),
      patterns.filter_map { |p| p[:room_capacity] }.max,
      rows.length
    ]
  end

  # Groups a section's meetings by everything except the day, so "Monday 8:00
  # in ANX 305" and "Wednesday 8:00 in ANX 305" become one "MW" pattern. A
  # section that also meets Friday at another hour keeps that as a second one.
  def meeting_patterns(rows)
    grouped = rows.group_by do |row|
      [ row[BEGIN_TIME_INDEX], row[END_TIME_INDEX], row[MEETING_TYPE_INDEX],
        row[BUILDING_INDEX], row[ROOM_NUMBER_INDEX] ]
    end

    grouped.map do |key, pattern_rows|
      begin_time, end_time, meeting_schedule_type, building_abbreviation, room_number = key

      {
        days: day_codes(pattern_rows),
        time: "#{format_hhmm(begin_time)}-#{format_hhmm(end_time)}",
        meeting_type: meeting_schedule_type,
        room: format_room(building_abbreviation, room_number),
        room_capacity: pattern_rows.first[ROOM_CAPACITY_INDEX]
      }
    end
  end

  # Week-ordered day letters for one pattern, e.g. "MW". Sorted by DAY_CODES
  # order, which starts on Monday the way a class schedule reads. The
  # day_of_week enum starts on Sunday, so it would put "U" first instead.
  # uniq guards against a meeting listed twice for the same day in two rooms.
  def day_codes(rows)
    rows
      .map { |row| row[DAY_OF_WEEK_INDEX] }
      .uniq
      .sort_by { |day| DAY_CODES.keys.index(day) }
      .map { |day| DAY_CODES.fetch(day) }
      .join
  end

  # Every meeting column lists one part per pattern, in the same order, so the
  # parts line up across columns: the second piece of meeting_days always goes
  # with the second piece of meeting_times and of room. A section with one
  # pattern, which is almost all of them, gets a plain single value.
  def join_patterns(values)
    return nil if values.compact_blank.empty?
    return values.first if values.length == 1

    values.map(&:presence).join(PATTERN_SEPARATOR)
  end

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
