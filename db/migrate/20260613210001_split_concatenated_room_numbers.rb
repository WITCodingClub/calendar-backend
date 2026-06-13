# frozen_string_literal: true

# Splits rooms whose number contains "/" (e.g. "201/202") into individual rooms
# and updates the meeting_time_rooms join table to point to each.
# These records were created before multi-room parsing was added.
class SplitConcatenatedRoomNumbers < ActiveRecord::Migration[8.0]
  def up
    concatenated = Room.where("number LIKE '%/%'")
    return unless concatenated.any?

    say "Splitting #{concatenated.count} concatenated room(s)"

    concatenated.each do |old_room|
      parts = old_room.number.split("/").map(&:strip).reject(&:blank?)
      next if parts.length <= 1

      new_rooms = parts.map do |num|
        Room.find_or_create_by!(building_id: old_room.building_id, number: num)
      end

      # Re-associate any meeting times from the old room to all split rooms
      Course::MeetingTimeRoom.where(room_id: old_room.id).find_each do |old_assoc|
        new_rooms.each do |new_room|
          Course::MeetingTimeRoom.find_or_create_by!(
            meeting_time_id: old_assoc.meeting_time_id,
            room_id:         new_room.id
          )
        end
        old_assoc.destroy!
      end

      old_room.destroy!
      say "  Split '#{old_room.number}' → #{parts.join(', ')} (building #{old_room.building_id})"
    end
  end

  def down
    say "Cannot reverse room split — skipping"
  end
end
