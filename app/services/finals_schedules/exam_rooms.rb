# frozen_string_literal: true

module FinalsSchedules
  # The rooms that a final exam location names. The finals PDF writes a
  # location as building abbreviations and room numbers, with
  # Room::LIST_SEPARATOR between rooms ("WENT 210 / CEIS 414A"). The parser
  # adds the rooms it finds, and the serializers, the ICS feed and the admin
  # pages read them back here.
  module ExamRooms
    # "WENT 210" or "WENT 2A": a building abbreviation, then a room number that
    # can end in letters. A building code can start with digits ("525HA 114").
    ROOM_PATTERN = /\b([A-Z0-9]*[A-Z])\s+(\d+[A-Z]*)/i

    Part = Data.define(:abbrev, :number) do
      def room_key = Room.number_key(number)
    end

    module_function

    # Each part of the location, or nil for a part that is not "ABBR 123".
    def parts(location)
      return [] if location.blank?

      location.split(Room::LIST_SEPARATOR).map do |text|
        match = text.match(ROOM_PATTERN)
        Part.new(abbrev: match[1], number: match[2].upcase) if match
      end
    end

    # The room of each part of each exam's location, or nil for a part with no
    # known room. Two queries, for one exam or many.
    # @return [Hash{FinalExam => Array<Room, nil>}]
    def part_rooms_for(exams)
      parts_by_exam = exams.index_with { |exam| parts(exam.location) }
      all_parts = parts_by_exam.values.flatten.compact
      return parts_by_exam if all_parts.empty?

      buildings_by_abbrev = Building.where(abbreviation: all_parts.map(&:abbrev).uniq).index_by(&:abbreviation)
      rooms_by_key = Room.where(building_id: buildings_by_abbrev.values.map(&:id))
                         .includes(:building)
                         .index_by { |room| [ room.building_id, Room.number_key(room.number) ] }

      parts_by_exam.transform_values do |exam_parts|
        exam_parts.map do |part|
          building = part && buildings_by_abbrev[part.abbrev]
          rooms_by_key[[ building.id, part.room_key ]] if building
        end
      end
    end

    # Names each part of the location that has a room, and keeps the text of
    # the other parts.
    def named_location(location, part_rooms)
      return location if location.blank?

      location.split(Room::LIST_SEPARATOR).each_with_index.map do |text, i|
        room = part_rooms[i]
        room ? "#{room.building.name} #{room.formatted_number}" : text
      end.join(Room::LIST_SEPARATOR)
    end

    # Adds a Room for each part whose building is known and whose room is not.
    # Returns the number of rooms made.
    def create_missing_rooms!(location)
      parts(location).compact.count do |part|
        building = Building.find_by(abbreviation: part.abbrev)
        next false if building.nil? || building.rooms.any? { |room| Room.number_key(room.number) == part.room_key }

        building.rooms.create!(number: part.number)
        Rails.logger.info("Created room #{part.number} in #{building.name}")
        true
      end
    end
  end
end
