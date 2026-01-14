# frozen_string_literal: true

# == Schema Information
#
# Table name: rooms
# Database name: primary
#
#  id          :bigint           not null, primary key
#  number      :string
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
  let(:building) { create(:building) }

  describe "#formatted_number" do
    it "pads single digit room numbers to 3 digits" do
      room = build(:room, building: building, number: 6)
      expect(room.formatted_number).to eq("006")
    end

    it "pads double digit room numbers to 3 digits" do
      room = build(:room, building: building, number: 42)
      expect(room.formatted_number).to eq("042")
    end

    it "keeps triple digit room numbers as-is" do
      room = build(:room, building: building, number: 123)
      expect(room.formatted_number).to eq("123")
    end

    it "formats room number 0 (TBD) as 000" do
      room = build(:room, building: building, number: 0)
      expect(room.formatted_number).to eq("000")
    end
  end

  describe "#floor" do
    it "returns the first digit of the room number" do
      room = build(:room, building: building, number: 312)
      expect(room.floor).to eq(3)
    end

    it "returns the number itself for single digit rooms" do
      room = build(:room, building: building, number: 6)
      expect(room.floor).to eq(6)
    end
  end
end
