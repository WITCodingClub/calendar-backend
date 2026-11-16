# frozen_string_literal: true

module Catalog
  # Writes a section's meetings (Catalog::BannerSection::Meeting) as meeting
  # time rows, one for each day, with their rooms.
  class MeetingTimesIngest < ApplicationService
    attr_reader :course, :meetings

    # Buildings and rooms by key, shared by the ingests of several courses.
    # A caller that ingests many courses calls preload once with the meetings
    # of all of them and passes the same object to each ingest. Each course
    # then sends no query for a building or room that is already here.
    class Locations
      attr_reader :buildings, :rooms

      def initialize
        @buildings = {}
        @rooms = {}
      end

      # Loads the buildings and rooms that the meetings name, in one query
      # each, and creates the ones that do not exist. A meeting with no
      # building is skipped: it gets the TBD building or none, which depends
      # on whether its course is online.
      def preload(meetings)
        load(Array(meetings).filter_map { |meeting| [ meeting.building, meeting.building_name, meeting.room_numbers ] if meeting.building.present? })
      end

      # Each entry is [building abbreviation, building name, room numbers].
      # Sends queries only for the buildings and rooms that are not loaded yet.
      def load(entries)
        missing_abbrs = entries.map(&:first).uniq - buildings.keys
        if missing_abbrs.any?
          Building.where(abbreviation: missing_abbrs).each { |b| buildings[b.abbreviation] = b }

          entries.uniq(&:first).each do |abbr, name, _rooms|
            # Insert first: the query above found no row, so a lookup would only repeat it.
            buildings[abbr] ||= Building.create_or_find_by!(abbreviation: abbr) do |b|
              b.name = name.presence || abbr
            end
          end
        end

        missing_rooms = entries.flat_map { |abbr, _name, numbers| numbers.map { |number| [ number, buildings[abbr] ] } }
                               .uniq { |number, building| [ number, building.id ] }
                               .reject { |number, building| rooms.key?([ number, building.id ]) }
        return if missing_rooms.empty?

        Room.where(building_id: missing_rooms.map { |_, building| building.id }.uniq, number: missing_rooms.map(&:first).uniq)
            .includes(:building)
            .each { |r| rooms[[ r.number, r.building_id ]] = r }

        missing_rooms.each do |number, building|
          rooms[[ number, building.id ]] ||= Room.create!(number: number, building: building)
        end
      end

      def rooms_for(abbr, numbers)
        building = buildings.fetch(abbr)
        numbers.map { |number| rooms.fetch([ number, building.id ]) }
      end
    end

    # Options:
    # - locations: a Locations object shared with the ingests of other courses.
    # - existing_meeting_times: the course's meeting times, loaded by the caller
    #   with their meeting_time_rooms. Without it, the ingest loads them itself.
    def initialize(course:, meetings:, **options)
      @course = course
      @meetings = Array(meetings)
      @locations = options[:locations] || Locations.new
      @existing_meeting_times = options[:existing_meeting_times]
      super()
    end

    # Upserts meeting times in place and returns the IDs of every row that was
    # created or updated, so callers can prune stale rows without touching the rest.
    def call
      places = meetings.to_h { |meeting| [ meeting, place_of(meeting) ] }
      @locations.load(places.values.compact)

      existing = @existing_meeting_times || Course::MeetingTime.where(course_id: course.id).includes(:meeting_time_rooms)
      @meeting_time_cache = existing.index_by { |mt| [ mt.start_date, mt.end_date, mt.begin_time, mt.end_time, mt.day_of_week ] }

      meetings.select(&:complete?).flat_map do |meeting|
        abbr, _name, numbers = places[meeting]
        abbr ? ingest_one(meeting, @locations.rooms_for(abbr, numbers)) : []
      end
    end

    private

    # [building abbreviation, building name, room numbers], or nil for an
    # online section with no building. Any other meeting with no building
    # gets the TBD building, and the TBD building gets its full name.
    def place_of(meeting)
      abbr = meeting.building
      if abbr.blank?
        return nil if Course::ScheduleType.online?(course.schedule_type)

        abbr = Building::TBD_ABBREVIATION
      end
      name = meeting.building_name.presence || (Building::TBD_NAME if abbr == Building::TBD_ABBREVIATION)
      [ abbr, name, meeting.room_numbers ]
    end

    def ingest_one(meeting, rooms)
      start_dt = meeting.start_date.in_time_zone.beginning_of_day
      end_dt   = meeting.end_date.in_time_zone.change(hour: 23, min: 59, sec: 59)

      meeting.days.map do |day|
        cache_key = [ start_dt, end_dt, meeting.begin_time, meeting.end_time, day ]
        meeting_time = @meeting_time_cache[cache_key] ||
                       Course::MeetingTime.new(course: course, start_date: start_dt, end_date: end_dt,
                                               begin_time: meeting.begin_time, end_time: meeting.end_time, day_of_week: day)
        meeting_time.assign_attributes(meeting_schedule_type: lab?(meeting) ? :laboratory : :lecture,
                                       meeting_type: :class_meeting,
                                       hours_week: meeting.hours)
        meeting_time.save!
        link_rooms(meeting_time, rooms)

        @meeting_time_cache[cache_key] = meeting_time
        meeting_time.id
      end
    end

    def link_rooms(meeting_time, rooms)
      # A meeting time created just now has no rooms yet, so skip the query.
      desired = rooms.index_by(&:id)
      existing = meeting_time.previously_new_record? ? [] : meeting_time.meeting_time_rooms.to_a

      existing.reject { |link| desired.key?(link.room_id) }.each(&:destroy)
      (desired.keys - existing.map(&:room_id)).each do |room_id|
        meeting_time.meeting_time_rooms.create!(room: desired[room_id])
      end
    end

    # getClassDetails meetings carry no schedule type, and the nightly sync
    # re-ingests them. Without the section's type every lab meeting went back
    # to "lecture" each night. A section's meetings share its schedule type.
    def lab?(meeting)
      return Course::ScheduleType.lab?(Course::ScheduleType.key_for_code(meeting.schedule_code)) if meeting.schedule_code

      Course::ScheduleType.lab?(course.schedule_type)
    end
  end
end
