# == Schema Information
#
# Table name: rooms
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

end
