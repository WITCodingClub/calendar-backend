# frozen_string_literal: true

# == Schema Information
#
# Table name: rooms
#
#  id                  :bigint           not null, primary key
#  floor               :integer          not null
#  formal_name         :string
#  number              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  building_id         :bigint           not null
#  twenty_five_live_id :integer
#
# Indexes
#
#  index_rooms_on_building_id             (building_id)
#  index_rooms_on_building_id_and_number  (building_id,number) UNIQUE
#  index_rooms_on_twenty_five_live_id     (twenty_five_live_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (building_id => buildings.id)
#
class Room < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rom

  belongs_to :building
  has_many :meeting_time_rooms, class_name: "Course::MeetingTimeRoom", dependent: :destroy
  has_many :meeting_times, through: :meeting_time_rooms, class_name: "Course::MeetingTime"

  before_save :set_floor

  def floor
    first_char = number.to_s[0].to_s
    first_char.match?(/\d/) ? first_char.to_i : 0
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

  private

  def set_floor
    self[:floor] = floor
  end
end
