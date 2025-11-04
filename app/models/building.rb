# frozen_string_literal: true

# == Schema Information
#
# Table name: buildings
# Database name: primary
#
#  id           :bigint           not null, primary key
#  abbreviation :string           not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_buildings_on_abbreviation  (abbreviation) UNIQUE
#  index_buildings_on_name          (name) UNIQUE
#
class Building < ApplicationRecord
  has_many :rooms, dependent: :restrict_with_exception

end
