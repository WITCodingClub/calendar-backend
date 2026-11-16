# frozen_string_literal: true

module Catalog
  # One weekly meeting of a section, as the public catalog API returns it.
  class MeetingTimeSerializer
    def initialize(meeting_time)
      @meeting_time = meeting_time
    end

    def as_json(*)
      return nil if @meeting_time.nil?

      {
        day:              @meeting_time.day_of_week,
        day_of_week:      Course::MeetingTime.day_of_weeks[@meeting_time.day_of_week],
        begin_time:       @meeting_time.fmt_begin_time_military,
        end_time:         @meeting_time.fmt_end_time_military,
        begin_time_12h:   @meeting_time.fmt_begin_time,
        end_time_12h:     @meeting_time.fmt_end_time,
        duration_minutes: Fields.duration_minutes(@meeting_time),
        meeting_type:     @meeting_time.meeting_schedule_type,
        all_day:          @meeting_time.all_day?,
        location:         location
      }
    end

    private

    def location
      building = @meeting_time.building
      return nil if building.nil?

      {
        display:  @meeting_time.building_room,
        building: { abbreviation: building.abbreviation, name: building.name },
        rooms:    @meeting_time.rooms.map { |room| { number: room.number, floor: room.floor } }
      }
    end
  end
end
