# frozen_string_literal: true

class MeetingTimesIngestService < ApplicationService
  attr_reader :course, :raw_meeting_times

  def initialize(course:, raw_meeting_times:, **options)
    @course = course
    @raw_meeting_times = Array(raw_meeting_times)
    @compute_hours_week = options.fetch(:compute_hours_week, true)
    @building_cache = {}
    @room_cache = {}
    super()
  end

  def call
    preload_buildings_and_rooms
    raw_meeting_times.each do |mt|
      ingest_one(mt)
    end
  end

  private

  ONLINE_SCHEDULE_TYPES = %w[online online_blended online_sync_lab online_sync_lecture].freeze

  def preload_buildings_and_rooms
    building_data = @raw_meeting_times.filter_map { |mt|
      abbr = (mt["building"] || mt[:building]).to_s.strip
      desc = (mt["buildingDescription"] || mt[:buildingDescription]).to_s.strip
      next if abbr.blank? && online_course?

      abbr = "TBD" if abbr.blank?
      desc = "To Be Determined" if abbr == "TBD" && desc.blank?
      [ abbr, desc ]
    }.uniq { |abbr, _| abbr }
    abbrs = building_data.map(&:first).uniq

    @building_cache = Building.where(abbreviation: abbrs).index_by(&:abbreviation)

    building_data.each do |abbr, name|
      next if @building_cache.key?(abbr)

      @building_cache[abbr] = Building.find_or_create_by!(abbreviation: abbr) do |b|
        b.name = name.presence || abbr
      end
    end

    return if @building_cache.empty?

    needed_rooms = @raw_meeting_times.each_with_object([]) { |mt, acc|
      raw_abbr = (mt["building"] || mt[:building]).to_s.strip
      abbr = if raw_abbr.blank?
               online_course? ? next : "TBD"
      else
               raw_abbr
      end
      building = @building_cache[abbr]
      next unless building

      parse_room_numbers((mt["room"] || mt[:room]).to_s.strip).each do |room_num|
        acc << [ room_num, building.id, building ]
      end
    }.uniq { |room_num, building_id, _| [ room_num, building_id ] }

    building_ids = needed_rooms.map { |_, bid, _| bid }.uniq
    room_numbers = needed_rooms.map { |rnum, _, _| rnum }.uniq

    @room_cache = Room.where(building_id: building_ids, number: room_numbers)
                      .includes(:building)
                      .index_by { |r| [ r.number, r.building_id ] }

    needed_rooms.each do |room_num, building_id, building|
      next if @room_cache.key?([ room_num, building_id ])

      room = Room.create!(number: room_num, building: building)
      @room_cache[[ room_num, building_id ]] = room
    end

    @meeting_time_cache = Course::MeetingTime.where(course_id: course.id)
                                             .includes(:meeting_time_rooms)
                                             .index_by { |mt| [ mt.start_date, mt.end_date, mt.begin_time, mt.end_time, mt.day_of_week_before_type_cast ] }
  end

  def ingest_one(mt)
    start_date_str = mt["startDate"] || mt[:startDate] || mt["meetingStartDate"] || mt[:meetingStartDate]
    end_date_str   = mt["endDate"]   || mt[:endDate]   || mt["meetingEndDate"]   || mt[:meetingEndDate]
    begin_time_str = mt["beginTime"] || mt[:beginTime]
    end_time_str   = mt["endTime"]   || mt[:endTime]

    start_dt = parse_date_to_beginning_of_day(start_date_str)
    end_dt   = parse_date_to_end_of_day(end_date_str)
    begin_hhmm = to_hhmm_format(begin_time_str)
    end_hhmm   = to_hhmm_format(end_time_str)

    return if start_dt.nil? || end_dt.nil? || begin_hhmm.nil? || end_hhmm.nil?

    days_map = {
      sunday: 0,
      monday: 1,
      tuesday: 2,
      wednesday: 3,
      thursday: 4,
      friday: 5,
      saturday: 6
    }

    active_days = days_map.select do |day_name, _day_num|
      to_boolean(mt[day_name.to_s] || mt[day_name])
    end

    return if active_days.empty?

    building_abbr = (mt["building"] || mt[:building]).to_s.strip
    building_name = (mt["buildingDescription"] || mt[:buildingDescription]).to_s.strip

    if building_abbr.blank?
      return if online_course?
      building_abbr = "TBD"
      building_name = "To Be Determined"
    end

    building = @building_cache[building_abbr] ||= Building.find_or_create_by!(abbreviation: building_abbr) do |b|
      b.name = building_name.presence || building_abbr
    end

    room_str = (mt["room"] || mt[:room]).to_s.strip
    rooms_for_mt = parse_room_numbers(room_str).map { |room_num|
      cache_key = [ room_num, building.id ]
      @room_cache[cache_key] ||= Room.find_or_create_by!(number: room_num, building: building)
    }

    meeting_schedule_type = map_schedule_type(mt["meetingScheduleType"] || mt[:meetingScheduleType] || mt["scheduleType"] || mt[:scheduleType])
    meeting_type          = map_meeting_type(mt["meetingType"] || mt[:meetingType])

    hours_per_day = if @compute_hours_week
                      compute_hours_per_day(begin_hhmm, end_hhmm)
    else
                      nil
    end

    active_days.each_value do |day_num|
      lookup_attrs = {
        course: course,
        start_date: start_dt,
        end_date: end_dt,
        begin_time: begin_hhmm,
        end_time: end_hhmm,
        day_of_week: day_num
      }

      update_attrs = {
        meeting_schedule_type: meeting_schedule_type,
        meeting_type: meeting_type,
        hours_week: hours_per_day
      }

      cache_key = [ start_dt, end_dt, begin_hhmm, end_hhmm, day_num ]
      meeting_time = @meeting_time_cache&.[](cache_key) || Course::MeetingTime.new(lookup_attrs)
      meeting_time.assign_attributes(update_attrs)
      meeting_time.save!

      desired_room_ids = rooms_for_mt.map(&:id).to_set
      existing_room_ids = meeting_time.meeting_time_rooms.map(&:room_id).to_set

      (existing_room_ids - desired_room_ids).each do |rid|
        meeting_time.meeting_time_rooms.find_by(room_id: rid)&.destroy
      end
      (desired_room_ids - existing_room_ids).each do |rid|
        meeting_time.meeting_time_rooms.create!(room_id: rid)
      end

      @meeting_time_cache[cache_key] = meeting_time if @meeting_time_cache
    end
  end

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
    when /\A\d{3,4}\z/
      # Banner returns beginTime/endTime as bare integers (e.g. 800, 1315, 0800)
      hhmm = str.to_i
      h = hhmm / 100
      m = hhmm % 100
      return nil if h > 23 || m > 59

      hhmm
    else
      nil
    end
  end

  def to_boolean(val)
    case val
    when true, "true", "TRUE", "Y", "y", 1, "1"
      true
    else
      false
    end
  end

  def parse_room_numbers(room_str)
    return [ "0" ] if room_str.blank?

    parts = room_str.to_s.strip.split("/").map(&:strip).reject(&:blank?)
    parts.empty? ? [ "0" ] : parts
  end

  def map_schedule_type(val)
    case val.to_s.strip.upcase
    when "LAB" then 2
    else 1
    end
  end

  def map_meeting_type(_val)
    1
  end

  def online_course?
    ONLINE_SCHEDULE_TYPES.include?(course.schedule_type.to_s)
  end

  def compute_hours_per_day(begin_hhmm, end_hhmm)
    begin_h = begin_hhmm / 100
    begin_m = begin_hhmm % 100
    begin_decimal = begin_h + (begin_m / 60.0)

    end_h = end_hhmm / 100
    end_m = end_hhmm % 100
    end_decimal = end_h + (end_m / 60.0)

    [ end_decimal - begin_decimal, 0 ].max.round
  end
end
