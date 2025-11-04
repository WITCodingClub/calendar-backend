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
require "rails_helper"

RSpec.describe Room do
  pending "add some examples to (or delete) #{__FILE__}"
end
