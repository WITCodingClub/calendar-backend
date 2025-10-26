# == Schema Information
#
# Table name: buildings
#
#  id           :bigint           not null, primary key
#  abbreviation :string           not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class Building < ApplicationRecord
  has_many :rooms
end
