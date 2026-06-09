# frozen_string_literal: true

class Room < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rom

  belongs_to :building
  has_many :meeting_times, class_name: "Course::MeetingTime", dependent: :restrict_with_exception

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
