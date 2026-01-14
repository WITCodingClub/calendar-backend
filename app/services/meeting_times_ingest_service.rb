# frozen_string_literal: true

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

    # Extract which days are active
    days_map = {
      sunday: 0,
      monday: 1,
      tuesday: 2,
      wednesday: 3,
      thursday: 4,
      friday: 5,
      saturday: 6
    }

    active_days = days_map.select do |day_name, day_num|
      to_boolean(mt[day_name.to_s] || mt[day_name])
    end

    # Skip if no days are active
    return if active_days.empty?

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

    # Calculate hours per day (not per week)
    hours_per_day = if @compute_hours_week
                      compute_hours_per_day(begin_hhmm, end_hhmm)
                    else
                      nil
                    end

    # Create a separate MeetingTime record for each active day
    active_days.each_value do |day_num|
      attrs = {
        course_id: course.id,
        room_id: room.id,
        start_date: start_dt,
        end_date: end_dt,
        begin_time: begin_hhmm,
        end_time: end_hhmm,
        day_of_week: day_num
      }

      MeetingTime.find_or_create_by!(attrs) do |mt_record|
        mt_record.meeting_schedule_type = meeting_schedule_type
        mt_record.meeting_type = meeting_type
        mt_record.hours_week = hours_per_day
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
    case str
    when /\A(\d{1,2}):(\d{2})\s*(AM|PM)\z/i
      h = Regexp.last_match(1).to_i
      m = Regexp.last_match(2).to_i
      meridian = Regexp.last_match(3).upcase
      h = (h % 12) + (meridian == "PM" ? 12 : 0)
      (h * 100) + m
    when /\A(\d{1,2}):(\d{2})\z/
      h = Regexp.last_match(1).to_i
      m = Regexp.last_match(2).to_i
      return nil if h > 23 || m > 59

      (h * 100) + m
    when /\A(\d{2})(\d{2})\z/
      # Handle HHMM format like "1000" or "1145" - already in correct format
      hhmm = str.to_i
      h = hhmm / 100
      m = hhmm % 100
      return nil if h > 23 || m > 59

      hhmm
    else
      nil
    end
  end

  # Banner often uses true/Y/1
  def to_boolean(val)
    case val
    when true, "true", "TRUE", "Y", "y", 1, "1"
      true
    else
      false
    end
  end

  # Extract numeric room; fallback to 0 if unknown (room_id is NOT NULL)
  def parse_room_number(room_str)
    return 0 if room_str.blank?

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

  # Compute hours per day: duration in hours for a single meeting
  def compute_hours_per_day(begin_hhmm, end_hhmm)
    # Convert HHMM to decimal hours for calculation
    begin_h = begin_hhmm / 100
    begin_m = begin_hhmm % 100
    begin_decimal = begin_h + (begin_m / 60.0)

    end_h = end_hhmm / 100
    end_m = end_hhmm % 100
    end_decimal = end_h + (end_m / 60.0)

    [end_decimal - begin_decimal, 0].max.round
  end

end
