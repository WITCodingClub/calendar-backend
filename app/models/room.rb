# == Schema Information
#
# Table name: rooms
# Database name: primary
#
#  id         :bigint           not null, primary key
#  number     :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Room < ApplicationRecord
  belongs_to :building

  def floor
    # get first digit of room number
    number.to_s[0].to_i
  end

end
