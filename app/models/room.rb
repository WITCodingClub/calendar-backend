# frozen_string_literal: true

# == Schema Information
#
# Table name: rooms
# Database name: primary
#
#  id          :bigint           not null, primary key
#  number      :string
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
  include PublicIdentifiable

  set_public_id_prefix :rom

  belongs_to :building
  has_many :meeting_times, dependent: :restrict_with_exception

  def floor
    # Extract first digit from the room number string
    match = number.to_s.match(/\d/)
    match ? match[0].to_i : 0
  end

  def formatted_number
    # If the room number is purely numeric, pad to 3 digits.
    # Otherwise, return as is.
    if number.to_s.match?(/\A\d+\z/)
      number.to_s.rjust(3, "0")
    else
      number.to_s
    end
  end

  def to_param
    public_id
  end

end
