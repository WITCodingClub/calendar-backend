# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_spaces
# Database name: primary
#
#  id            :bigint           not null, primary key
#  building_name :string
#  formal_name   :string
#  max_capacity  :integer
#  space_name    :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  space_id      :integer          not null
#
# Indexes
#
#  index_twenty_five_live_spaces_on_space_id  (space_id) UNIQUE
#
module TwentyFiveLive
  class Space < ApplicationRecord
    self.table_name = "twenty_five_live_spaces"

    has_many :space_reservations, class_name: "TwentyFiveLive::SpaceReservation", dependent: :destroy

    validates :space_id, presence: true, uniqueness: true

    def self.find_or_create_by_space_id(attrs)
      find_or_create_by(space_id: attrs[:space_id]) do |space|
        space.assign_attributes(attrs.except(:space_id))
      end
    end

  end
end
