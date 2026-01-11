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
require "rails_helper"

RSpec.describe Building do
  describe "database constraints" do
    it "is valid with valid attributes" do
      building = build(:building)
      expect(building).to be_valid
    end

    it "enforces name presence at database level" do
      building = build(:building, name: nil)
      expect { building.save(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces abbreviation presence at database level" do
      building = build(:building, abbreviation: nil)
      expect { building.save(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces name uniqueness at database level" do
      create(:building, name: "Watson Hall", abbreviation: "WAT")
      duplicate = build(:building, name: "Watson Hall", abbreviation: "WAT2")
      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces abbreviation uniqueness at database level" do
      create(:building, name: "Watson Hall", abbreviation: "WAT")
      duplicate = build(:building, name: "Watson Hall 2", abbreviation: "WAT")
      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it "has many rooms" do
      building = create(:building)
      room1 = create(:room, building: building, number: "101")
      room2 = create(:room, building: building, number: "102")

      expect(building.rooms).to include(room1, room2)
    end

    it "prevents deletion when rooms exist" do
      building = create(:building)
      create(:room, building: building)

      expect { building.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end

    it "can be deleted when no rooms exist" do
      building = create(:building)
      expect { building.destroy }.to change(Building, :count).by(-1)
    end
  end

  describe "public_id" do
    it "generates a public_id with bld prefix" do
      building = create(:building)
      expect(building.public_id).to start_with("bld_")
    end
  end
end
