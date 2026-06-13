class FixRoomFloorConstraintForLetterPrefixedNumbers < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :rooms, name: "rooms_floor_matches_number_prefix"
    add_check_constraint :rooms,
      "SUBSTRING(number FROM 1 FOR 1) !~ '^[0-9]$' OR SUBSTRING(number FROM 1 FOR 1) = floor::text",
      name: "rooms_floor_matches_number_prefix"
  end

  def down
    remove_check_constraint :rooms, name: "rooms_floor_matches_number_prefix"
    add_check_constraint :rooms,
      "SUBSTRING(number FROM 1 FOR 1) = floor::text",
      name: "rooms_floor_matches_number_prefix"
  end
end
