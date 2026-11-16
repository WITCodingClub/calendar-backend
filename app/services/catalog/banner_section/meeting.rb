# frozen_string_literal: true

module Catalog
  class BannerSection
    # One meeting of a section: the dates, the hours, the days, and the place.
    # Dates are Date, hours are HHMM integers (1315), and days are the keys of
    # Course::MeetingTime.day_of_weeks. A value Banner did not send, or sent
    # in a form that does not parse, is nil.
    Meeting = Data.define(:start_date, :end_date, :begin_time, :end_time, :days,
                          :building, :building_name, :room, :schedule_code) do
      # A meetingTime of the class search. Courses::Processor builds the same
      # shape from the meetings a student uploads.
      def self.from_search(mt)
        mt = mt.to_h.stringify_keys
        new(
          start_date: parse_date(mt["startDate"] || mt["meetingStartDate"]),
          end_date: parse_date(mt["endDate"] || mt["meetingEndDate"]),
          begin_time: parse_time(mt["beginTime"]),
          end_time: parse_time(mt["endTime"]),
          days: Course::MeetingTime.day_of_weeks.keys.select { |day| BannerSection::TRUE_VALUES.include?(mt[day]) },
          building: mt["building"].to_s.strip,
          building_name: mt["buildingDescription"].to_s.strip,
          room: mt["room"].to_s.strip,
          schedule_code: (mt["meetingScheduleType"] || mt["scheduleType"]).to_s.strip.upcase.presence
        )
      end

      # A meeting of Catalog::LeopardWebClient.get_class_details, from
      # getFacultyMeetingTimes, which uses its own key names.
      def self.from_class_details(mt)
        from_search(
          "startDate" => mt["startDate"], "endDate" => mt["endDate"],
          "beginTime" => mt["startTime"], "endTime" => mt["endTime"],
          "building" => mt["building"], "buildingDescription" => mt["building_description"],
          "room" => mt["room"], **mt["days"].to_h
        )
      end

      # Banner lists a meeting once for each instructor, sometimes with the
      # room on one copy only. Keeps one meeting for each dates, hours, and
      # days, with a real room when one copy has it.
      def self.dedupe(meetings)
        meetings.group_by(&:schedule_key).map do |_key, copies|
          copies.find { |meeting| !meeting.tbd_location? } || copies.first
        end
      end

      # Banner sends ISO dates in some answers and 01/12/2027 in others.
      def self.parse_date(value)
        str = value.to_s.strip
        return nil if str.empty?

        str.include?("/") ? Date.strptime(str, "%m/%d/%Y") : Date.iso8601(str)
      rescue ArgumentError
        nil
      end

      # "1315" and "800" from Banner, "13:15" and "1:15 PM" from an upload.
      def self.parse_time(value)
        str = value.to_s.strip
        if (match = str.match(/\A(\d{1,2}):(\d{2})\s*(AM|PM)?\z/i))
          hours = match[1].to_i
          hours = (hours % 12) + (match[3].casecmp?("PM") ? 12 : 0) if match[3]
          minutes = match[2].to_i
        elsif str.match?(/\A\d{3,4}\z/)
          hours, minutes = str.to_i.divmod(100)
        else
          return nil
        end
        return nil if hours > 23 || minutes > 59

        (hours * 100) + minutes
      end

      # Dates, hours, and at least one day: enough for a meeting time row.
      def complete?
        start_date && end_date && begin_time && end_time && days.any?
      end

      def schedule_key
        [ start_date, end_date, begin_time, end_time, days ]
      end

      # The rule of Building#tbd? and Room#tbd?, read before the rows exist.
      # A meeting with no building has no place at all.
      def tbd_location?
        return true if building.blank?

        Building.new(abbreviation: building, name: building_name.presence || building).tbd? ||
          room_numbers.all? { |number| Room.new(number: number).tbd? }
      end

      # "112/114" names two rooms. A blank room is room "0".
      def room_numbers
        parts = room.split("/").map(&:strip).compact_blank
        parts.empty? ? [ Room::TBD_NUMBER ] : parts
      end

      def hours
        start, finish = [ begin_time, end_time ].map { |hhmm| (hhmm / 100) + ((hhmm % 100) / 60.0) }
        [ finish - start, 0 ].max.round
      end
    end
  end
end
