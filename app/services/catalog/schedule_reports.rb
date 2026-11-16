# frozen_string_literal: true

require "csv"

module Catalog
  # The public CSV reports of course schedule data (Feeds::ReportsController),
  # for BI tools such as Power BI and Excel. Course data only: never put user
  # data in these reports.
  class ScheduleReports
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

    # The columns of one meeting-time-by-room row, and the SQL of each. pluck
    # type-casts enum columns, so season, day_of_week and meeting_type arrive
    # as their string keys ("fall", "monday", "lecture").
    COLUMNS = {
      term_uid:              "terms.uid",
      season:                "terms.season",
      year:                  "terms.year",
      crn:                   "courses.crn",
      subject:               "courses.subject",
      course_number:         "courses.course_number",
      section_number:        "courses.section_number",
      title:                 "courses.title",
      schedule_type:         "courses.schedule_type",
      status:                "courses.status",
      credit_hours:          "courses.credit_hours",
      faculty:               Arel.sql(FACULTY_NAMES_SQL),
      seats_capacity:        "courses.seats_capacity",
      seats_available:       "courses.seats_available",
      day_of_week:           "course_meeting_times.day_of_week",
      begin_time:            "course_meeting_times.begin_time",
      end_time:              "course_meeting_times.end_time",
      meeting_type:          "course_meeting_times.meeting_schedule_type",
      building_abbreviation: "buildings.abbreviation",
      building_name:         "buildings.name",
      room_number:           "rooms.number",
      room_capacity:         "rooms.capacity"
    }.freeze

    Row = Data.define(*COLUMNS.keys) do
      def term_name = "#{season.capitalize} #{year}"

      # Banner reports seats, not heads, so current enrollment is the
      # difference. Blank rather than a wrong 0 when either side is missing.
      def enrollment_current
        seats_capacity - seats_available unless seats_capacity.nil? || seats_available.nil?
      end
    end

    # term_uid limits the meeting time reports to one term.
    def initialize(term_uid: nil)
      @term_uid = term_uid.presence
    end

    # One row per meeting time in one room. Use this grain for room and time
    # questions.
    def meeting_times_csv
      CSV.generate do |csv|
        csv << MEETING_TIMES_HEADERS
        rows.each do |row|
          csv << [
            row.term_uid, row.term_name,
            row.crn, row.subject, row.course_number, row.section_number, row.title,
            row.schedule_type, row.status, row.credit_hours, row.faculty,
            row.seats_capacity, row.seats_available, row.enrollment_current,
            row.day_of_week, Course::MeetingTime.day_of_weeks.fetch(row.day_of_week),
            Hhmm.format(row.begin_time), Hhmm.format(row.end_time),
            row.meeting_type,
            row.building_abbreviation, row.building_name, format_room_number(row.room_number),
            format_room(row.building_abbreviation, row.room_number), row.room_capacity
          ]
        end
      end
    end

    # One row per section, with the meeting days collapsed into a "MW" style
    # pattern. A section that meets twice a week reads as one course here,
    # where the meeting times report shows it as two rows.
    def sections_csv
      CSV.generate do |csv|
        csv << SECTIONS_HEADERS
        # group_by keeps first-seen order, so the SQL ordering carries through.
        rows.group_by { |row| [ row.term_uid, row.crn ] }.each_value { |section_rows| csv << section_row(section_rows) }
      end
    end

    # The terms with schedule data, so every row is a term the meeting times
    # report can answer for.
    def terms_csv
      # Subquery, not a join: the chronological scope orders by a CASE expression,
      # which Postgres rejects alongside SELECT DISTINCT.
      with_schedule = Course.where(id: Course::MeetingTime.select(:course_id)).select(:term_id)
      terms  = Term.where(id: with_schedule).chronological
                   .pluck("terms.uid", "terms.season", "terms.year", "terms.start_date", "terms.end_date")
      counts = Course::MeetingTime.joins(course: :term).group("terms.uid").distinct.count

      CSV.generate do |csv|
        csv << TERMS_HEADERS
        terms.each do |uid, season, year, start_date, end_date|
          csv << [ uid, "#{season.capitalize} #{year}", season, year, start_date, end_date, counts[uid] ]
        end
      end
    end

    private

    # The one query both CSV reports read, ordered so a section's meetings
    # arrive together and in week order.
    def rows
      scope = Course::MeetingTime.joins(course: :term)
      scope = scope.where(terms: { uid: @term_uid }) if @term_uid

      # LEFT JOIN: a meeting time with no room assigned (online, TBD) must still
      # appear. A meeting time booked into two rooms yields one row per room, so
      # the grain of this query is meeting-time-by-room, not meeting-time.
      scope = scope.left_joins(meeting_time_rooms: { room: :building })

      # DISTINCT: a concurrent-ingest race can leave identical meeting time rows
      # (e.g. CRN 17294 in 202710 has 5 copies); the reports must not repeat them.
      scope
        .distinct
        .order(Arel.sql("terms.uid, courses.crn, course_meeting_times.day_of_week, " \
                        "course_meeting_times.begin_time, buildings.abbreviation, rooms.number"))
        .pluck(*COLUMNS.values)
        .map { |values| Row.new(*values) }
    end

    # Collapses one section's meeting-time-by-room rows into a single row.
    def section_row(rows)
      first    = rows.first
      patterns = meeting_patterns(rows)

      [
        first.term_uid, first.term_name,
        first.crn, first.subject, first.course_number, first.section_number, first.title,
        first.schedule_type, first.status, first.credit_hours, first.faculty,
        first.seats_capacity, first.seats_available, first.enrollment_current,
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
      rows.group_by { |row| [ row.begin_time, row.end_time, row.meeting_type, row.building_abbreviation, row.room_number ] }
          .map do |_key, pattern_rows|
            row = pattern_rows.first
            {
              days:          day_codes(pattern_rows),
              time:          "#{Hhmm.format(row.begin_time)}-#{Hhmm.format(row.end_time)}",
              meeting_type:  row.meeting_type,
              room:          format_room(row.building_abbreviation, row.room_number),
              room_capacity: row.room_capacity
            }
          end
    end

    # Week-ordered day letters for one pattern, e.g. "MW". Sorted by DAY_CODES
    # order, which starts on Monday the way a class schedule reads. The
    # day_of_week enum starts on Sunday, so it would put "U" first instead.
    # uniq guards against a meeting listed twice for the same day in two rooms.
    def day_codes(rows)
      rows.map(&:day_of_week).uniq.sort_by { |day| DAY_CODES.keys.index(day) }.map { |day| DAY_CODES.fetch(day) }.join
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

    # Room#formatted_number pads a numeric room to 3 digits, so "5" and "005"
    # sort and group as one room in a BI tool.
    def format_room_number(number)
      Room.new(number: number).formatted_number if number.present?
    end

    # One label ("ANX 305"), so a BI tool can group by room without joining
    # two columns itself.
    def format_room(building_abbreviation, number)
      return nil if building_abbreviation.blank?

      [ building_abbreviation, format_room_number(number) ].compact.join(" ")
    end
  end
end
