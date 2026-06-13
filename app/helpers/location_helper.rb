# frozen_string_literal: true

module LocationHelper
  module_function

  def tbd_building?(building)
    return false unless building

    building.name.blank? ||
      building.abbreviation.blank? ||
      building.name&.downcase&.include?("to be determined") ||
      building.name&.downcase&.include?("tbd") ||
      building.abbreviation&.downcase == "tbd"
  end

  def tbd_room?(room)
    return false unless room

    room.number == 0
  end

  def tbd_location?(building, room)
    tbd_building?(building) || tbd_room?(room)
  end
end
