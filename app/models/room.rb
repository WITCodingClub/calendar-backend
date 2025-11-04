# frozen_string_literal: true

# == Schema Information
#
# Table name: rooms
# Database name: primary
#
#  id          :bigint           not null, primary key
#  number      :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  building_id :bigint           not null
#
# Indexes
#
#  index_rooms_on_building_id  (building_id)
#
# Foreign Keys
#
#  fk_rails_...  (building_id => buildings.id)
#
class Room < ApplicationRecord
  belongs_to :building

  def floor
    # get first digit of room number
    number.to_s[0].to_i
  end

  def formatted_number
    # Pad room numbers to 3 digits (e.g., 6 becomes "006")
    number.to_s.rjust(3, "0")
  end

end
