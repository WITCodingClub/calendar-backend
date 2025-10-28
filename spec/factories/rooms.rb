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
#  fk_rails_rooms_building_id  (building_id => buildings.id)
#
FactoryBot.define do
  factory :room do
    
  end
end
