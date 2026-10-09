# frozen_string_literal: true

module Catalog
  class MeetingTimesIngest < ApplicationService
    attr_reader :course, :raw_meeting_times

    # Buildings and rooms by key, shared by the ingests of several courses.
    # A caller that ingests many courses calls preload once with the meeting
    # times of all of them and passes the same object to each ingest. Each
    # course then sends no query for a building or room that is already here.
    class Locations
      attr_reader :buildings, :rooms

      def initialize
        @buildings = {}
        @rooms = {}
      end

      # Loads the buildings and rooms that the meeting times name, in one query
      # each, and creates the ones that do not exist. A meeting time with no
      # building is skipped: it gets the TBD building or none, which depends on
      # whether its course is online.
      def preload(raw_meeting_times)
        entries = Array(raw_meeting_times).filter_map do |mt|
          abbr = (mt["building"] || mt[:building]).to_s.strip
          next if abbr.blank?

          [ abbr, (mt["buildingDescription"] || mt[:buildingDescription]).to_s.strip, (mt["room"] || mt[:room]).to_s.strip ]
        end
        load(entries)
      end

      # Each entry is [building abbreviation, building description, room string].
      # Sends queries only for the buildings and rooms that are not loaded yet.
      def load(entries)
        missing_abbrs = entries.map(&:first).uniq - buildings.keys
        if missing_abbrs.any?
          Building.where(abbreviation: missing_abbrs).each { |b| buildings[b.abbreviation] = b }

          entries.uniq(&:first).each do |abbr, desc, _room|
            # Insert first: the query above found no row, so a lookup would only repeat it.
            buildings[abbr] ||= Building.create_or_find_by!(abbreviation: abbr) do |b|
              b.name = desc.presence || abbr
            end
          end
        end

        missing_rooms = entries.flat_map { |abbr, _desc, room|
          building = buildings[abbr]
          Catalog::MeetingTimesIngest.parse_room_numbers(room).map { |room_num| [ room_num, building ] }
        }.uniq { |room_num, building| [ room_num, building.id ] }
                               .reject { |room_num, building| rooms.key?([ room_num, building.id ]) }
        return if missing_rooms.empty?

        Room.where(building_id: missing_rooms.map { |_, building| building.id }.uniq, number: missing_rooms.map(&:first).uniq)
            .includes(:building)
            .each { |r| rooms[[ r.number, r.building_id ]] = r }

        missing_rooms.each do |room_num, building|
          rooms[[ room_num, building.id ]] ||= Room.create!(number: room_num, building: building)
        end
      end
    end

    # Options:
    # - locations: a Locations object shared with the ingests of other courses.
    # - existing_meeting_times: the course's meeting times, loaded by the caller
    #   with their meeting_time_rooms. Without it, the ingest loads them itself.
    def initialize(course:, raw_meeting_times:, **options)
      @course = course
      @raw_meeting_times = Array(raw_meeting_times)
      @compute_hours_week = options.fetch(:compute_hours_week, true)
      @locations = options[:locations] || Locations.new
      @existing_meeting_times = options[:existing_meeting_times]
      super()
    end

    # "112/114" names two rooms. A blank room string means room "0".
    def self.parse_room_numbers(room_str)
      return [ "0" ] if room_str.blank?

      parts = room_str.to_s.strip.split("/").map(&:strip).reject(&:blank?)
      parts.empty? ? [ "0" ] : parts
    end

    # Banner's getFacultyMeetingTimes payload uses its own key names. Reshape it
    # into the keys ingest_one reads, so every caller that pulls from LeopardWeb
    # feeds this service the same shape.
    def self.normalize_leopard_web(meeting_times)
      Array(meeting_times).map do |lw_mt|
        {
          "startDate"           => lw_mt["startDate"],
          "endDate"             => lw_mt["endDate"],
          "beginTime"           => lw_mt["startTime"],
          "endTime"             => lw_mt["endTime"],
          "building"            => lw_mt["building"],
          "buildingDescription" => lw_mt["building_description"],
          "room"                => lw_mt["room"],
          "monday"              => lw_mt.dig("days", "monday"),
          "tuesday"             => lw_mt.dig("days", "tuesday"),
          "wednesday"           => lw_mt.dig("days", "wednesday"),
          "thursday"            => lw_mt.dig("days", "thursday"),
          "friday"              => lw_mt.dig("days", "friday"),
          "saturday"            => lw_mt.dig("days", "saturday"),
          "sunday"              => lw_mt.dig("days", "sunday")
        }
      end
    end

    # Upserts meeting times in place and returns the IDs of every row that was
    # created or updated, so callers can prune stale rows without touching the rest.
    def call
      preload_buildings_and_rooms
      @touched_meeting_time_ids = []
      raw_meeting_times.each do |mt|
        ingest_one(mt)
      end
      @touched_meeting_time_ids
    end

    private

    ONLINE_SCHEDULE_TYPES = %w[online online_blended online_sync_lab online_sync_lecture].freeze

    def preload_buildings_and_rooms
      entries = @raw_meeting_times.filter_map do |mt|
        abbr = (mt["building"] || mt[:building]).to_s.strip
        desc = (mt["buildingDescription"] || mt[:buildingDescription]).to_s.strip
        next if abbr.blank? && online_course?

        abbr = "TBD" if abbr.blank?
        desc = "To Be Determined" if abbr == "TBD" && desc.blank?
        [ abbr, desc, (mt["room"] || mt[:room]).to_s.strip ]
      end
      @locations.load(entries)

      existing = @existing_meeting_times || Course::MeetingTime.where(course_id: course.id).includes(:meeting_time_rooms)
      @meeting_time_cache = existing.index_by { |mt| [ mt.start_date, mt.end_date, mt.begin_time, mt.end_time, mt.day_of_week_before_type_cast ] }
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

      building = @locations.buildings[building_abbr] ||= Building.find_or_create_by!(abbreviation: building_abbr) do |b|
        b.name = building_name.presence || building_abbr
      end

      room_str = (mt["room"] || mt[:room]).to_s.strip
      rooms_for_mt = self.class.parse_room_numbers(room_str).map { |room_num|
        cache_key = [ room_num, building.id ]
        @locations.rooms[cache_key] ||= Room.find_or_create_by!(number: room_num, building: building)
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
        meeting_time = @meeting_time_cache[cache_key] || Course::MeetingTime.new(lookup_attrs)
        meeting_time.assign_attributes(update_attrs)
        meeting_time.save!

        # A meeting time created just now has no rooms yet, so skip the query.
        desired_rooms = rooms_for_mt.index_by(&:id)
        existing_links = meeting_time.previously_new_record? ? [] : meeting_time.meeting_time_rooms.to_a

        existing_links.reject { |link| desired_rooms.key?(link.room_id) }.each(&:destroy)
        (desired_rooms.keys - existing_links.map(&:room_id)).each do |rid|
          meeting_time.meeting_time_rooms.create!(room: desired_rooms[rid])
        end

        @meeting_time_cache[cache_key] = meeting_time
        @touched_meeting_time_ids << meeting_time.id
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
end
