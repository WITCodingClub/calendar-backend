# app/services/meeting_times_ingest_service.rb
class MeetingTimesIngestService < ApplicationService
  attr_reader :course, :raw_meeting_times

  # options:
  # - compute_hours_week: true/false (default true)
  def initialize(course:, raw_meeting_times:, **options)
    @course = course
    @raw_meeting_times = Array(raw_meeting_times)
    @compute_hours_week = options.fetch(:compute_hours_week, true)
    super()
  end

  def call
    raw_meeting_times.each do |mt|
      ingest_one(mt)
    end
  end

  private

  def ingest_one(mt)
    # Extract (support symbol/string keys and both field name formats)
    start_date_str = mt["startDate"] || mt[:startDate] || mt["meetingStartDate"] || mt[:meetingStartDate]
    end_date_str   = mt["endDate"]   || mt[:endDate]   || mt["meetingEndDate"]   || mt[:meetingEndDate]
    begin_time_str = mt["beginTime"] || mt[:beginTime]
    end_time_str   = mt["endTime"]   || mt[:endTime]

    start_dt = parse_date_to_beginning_of_day(start_date_str)
    end_dt   = parse_date_to_end_of_day(end_date_str)
    begin_hhmm = to_hhmm_format(begin_time_str)
    end_hhmm   = to_hhmm_format(end_time_str)

    return if start_dt.nil? || end_dt.nil? || begin_hhmm.nil? || end_hhmm.nil?

    days = {
      monday:    to_bool(mt["monday"]    || mt[:monday]),
      tuesday:   to_bool(mt["tuesday"]   || mt[:tuesday]),
      wednesday: to_bool(mt["wednesday"] || mt[:wednesday]),
      thursday:  to_bool(mt["thursday"]  || mt[:thursday]),
      friday:    to_bool(mt["friday"]    || mt[:friday]),
      saturday:  to_bool(mt["saturday"]  || mt[:saturday]),
      sunday:    to_bool(mt["sunday"]    || mt[:sunday])
    }

    # Building is required by Room
    building_abbr = (mt["building"] || mt[:building]).to_s.strip
    building_name = (mt["buildingDescription"] || mt[:buildingDescription]).to_s.strip
    building = Building.find_or_create_by!(abbreviation: building_abbr) do |b|
      b.name = building_name.presence || building_abbr
    end

    # Room is required by schema
    room_str = (mt["room"] || mt[:room]).to_s.strip
    room_number = parse_room_number(room_str)
    room = Room.find_or_create_by!(number: room_number, building: building)

    # Optional schedule/meeting type mappings (ints per schema)
    meeting_schedule_type = map_schedule_type(mt["meetingScheduleType"] || mt[:meetingScheduleType] || mt["scheduleType"] || mt[:scheduleType])
    meeting_type          = map_meeting_type(mt["meetingType"] || mt[:meetingType])

    attrs = {
      course_id: course.id,
      room_id: room.id,
      start_date: start_dt,
      end_date: end_dt,
      begin_time: begin_hhmm,
      end_time: end_hhmm
    }.merge(days)

    MeetingTime.find_or_create_by!(attrs) do |mt_record|
      mt_record.meeting_schedule_type = meeting_schedule_type
      mt_record.meeting_type = meeting_type
      if @compute_hours_week
        mt_record.hours_week = compute_hours_week(begin_hhmm, end_hhmm, days)
      end
    end
  end

  # Helpers

  def parse_date_to_beginning_of_day(value)
    date = parse_date(value)
    return nil unless date
    Time.zone.local(date.year, date.month, date.day, 0, 0, 0)
  end

  def parse_date_to_end_of_day(value)
    date = parse_date(value)
    return nil unless date
    Time.zone.local(date.year, date.month, date.day, 23, 59, 59)
  end

  def parse_date(value)
    return nil if value.nil? || value.to_s.strip.empty?
    str = value.to_s.strip
    Date.iso8601(str)
  rescue ArgumentError
    begin
      Date.strptime(str, "%m/%d/%Y")
    rescue ArgumentError
      nil
    end
  end

  # Convert "10:00 AM"/ "22:15" / "1000" → HHMM integer format
  def to_hhmm_format(value)
    return nil if value.nil? || value.to_s.strip.empty?
    str = value.to_s.strip
    if str =~ /\A(\d{1,2}):(\d{2})\s*(AM|PM)\z/i
      h = Regexp.last_match(1).to_i
      m = Regexp.last_match(2).to_i
      meridian = Regexp.last_match(3).upcase
      h = (h % 12) + (meridian == "PM" ? 12 : 0)
      (h * 100) + m
    elsif str =~ /\A(\d{1,2}):(\d{2})\z/
      h = Regexp.last_match(1).to_i
      m = Regexp.last_match(2).to_i
      return nil if h > 23 || m > 59
      (h * 100) + m
    elsif str =~ /\A(\d{2})(\d{2})\z/
      # Handle HHMM format like "1000" or "1145" - already in correct format
      h = Regexp.last_match(1).to_i
      m = Regexp.last_match(2).to_i
      return nil if h > 23 || m > 59
      (h * 100) + m
    else
      nil
    end
  end

  # Banner often uses true/Y/1
  def to_bool(val)
    case val
    when true, "true", "TRUE" then true
    when "Y", "y"             then true
    when 1, "1"               then true
    else
      false
    end
  end

  # Extract numeric room; fallback to 0 if unknown (room_id is NOT NULL)
  def parse_room_number(room_str)
    return 0 if room_str.nil? || room_str.empty?
    if room_str =~ /(\d+)/
      Regexp.last_match(1).to_i
    else
      0
    end
  end

  # Map schedule type string → integer; returns nil if unknown
  def map_schedule_type(val)
    return nil if val.nil?
    case val.to_s.strip.upcase
    when "LEC"   then 1 # lecture
    when "LAB"   then 2 # laboratory
    else
      nil
    end
  end

  # Map meeting type string → integer; returns nil if unknown
  def map_meeting_type(val)
    return nil if val.nil?
    case val.to_s.strip.upcase
    when "CLAS" then 1 # class_meeting
    else
      nil
    end
  end

  # Compute weekly hours: duration in hours × number of true days
  def compute_hours_week(begin_hhmm, end_hhmm, days)
    # Convert HHMM to decimal hours for calculation
    begin_h = begin_hhmm / 100
    begin_m = begin_hhmm % 100
    begin_decimal = begin_h + (begin_m / 60.0)

    end_h = end_hhmm / 100
    end_m = end_hhmm % 100
    end_decimal = end_h + (end_m / 60.0)

    per_day_hours = [end_decimal - begin_decimal, 0].max
    day_count = days.values.count(true)
    (per_day_hours * day_count).round
  end
end
