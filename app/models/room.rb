class Room < ApplicationRecord
  belongs_to :building

  def floor
    # get first digit of room number
    number.to_s[0].to_i
  end

end
