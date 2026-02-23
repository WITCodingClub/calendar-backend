# frozen_string_literal: true

# Helper module for location-related checks (TBD buildings/rooms)
# Used by CourseScheduleSyncable, ProcessedEventsBuilder, and cleanup jobs
module LocationHelper
  module_function

  # Check if building is TBD/placeholder
  # LeopardWeb sends null/empty for unassigned locations, not "TBD" placeholders
  def tbd_building?(building)
    return false unless building

    # Empty/blank building means location not yet assigned
    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase&.include?("tbd") ||
      building.abbreviation&.downcase == "tbd"
  end

  # Check if room is TBD/placeholder (room 0 or room name contains TBD)
  def tbd_room?(room)
    return false unless room

    room.number == 0
    # Note: Room model in production only has 'number', not 'name'
    # If room.name is added later, uncomment these lines:
    # room.name&.downcase&.include?("tbd") ||
    # room.name&.downcase&.include?("to be determined")
  end

  # Check if either building or room is TBD
  def tbd_location?(building, room)
    tbd_building?(building) || tbd_room?(room)
  end
end
