# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::ExamRooms do
  def rooms(exam) = described_class.part_rooms_for([ exam ])[exam].compact

  describe ".part_rooms_for" do
    # Abbreviations avoid digits (the matcher reads letters) and fixture names.
    let!(:building) { create(:building, abbreviation: "ZZQ", name: "Synthetic Hall") }
    let!(:room) { create(:room, building: building, number: "112") }
    let!(:lab) { create(:room, building: building, number: "205") }

    it "returns no rooms without a location" do
      exam = build(:final_exam, location: nil)

      expect(rooms(exam)).to eq([])
      expect(exam.location_with_names).to be_nil
    end

    it "returns no rooms when the location has no room pattern" do
      expect(rooms(build(:final_exam, location: "Online"))).to eq([])
    end

    it "finds rooms in a combined location" do
      exam = build(:final_exam, location: "ZZQ 112 / ZZQ 205")

      expect(rooms(exam)).to eq([ room, lab ])
    end

    it "skips an unknown building or room" do
      exam = build(:final_exam, location: "NOPE 112 / ZZQ 999 / ZZQ 112")

      expect(rooms(exam)).to eq([ room ])
    end

    it "builds a location with building names" do
      exam = build(:final_exam, location: "ZZQ 112")

      expect(exam.location_with_names).to eq("Synthetic Hall 112")
    end

    it "matches a room with a letter suffix" do
      lettered = create(:room, building: building, number: "402A")
      create(:room, building: building, number: "402")
      exam = build(:final_exam, location: "ZZQ 402A")

      expect(rooms(exam)).to eq([ lettered ])
    end

    it "matches a room that the catalog stores with leading zeros" do
      padded = create(:room, building: building, number: "011")
      exam = build(:final_exam, location: "ZZQ 11")

      expect(rooms(exam)).to eq([ padded ])
    end

    it "matches a building code that starts with digits" do
      numbered = create(:building, abbreviation: "525ZQ", name: "Numbered Hall")
      numbered_room = create(:room, building: numbered, number: "114")

      expect(rooms(build(:final_exam, location: "525ZQ 114"))).to eq([ numbered_room ])
    end

    it "finds the rooms of many exams with one set of queries" do
      first = build(:final_exam, location: "ZZQ 112")
      second = build(:final_exam, location: "ZZQ 205 / NOPE 1")
      online = build(:final_exam, location: "Online")

      expect(described_class.part_rooms_for([ first, second, online ]).transform_values(&:compact))
        .to eq(first => [ room ], second => [ lab ], online => [])
    end

    it "builds a location from rooms it is given" do
      exam = build(:final_exam, location: "ZZQ 205 / NOPE 1")

      expect(exam.location_with_names([ lab, nil ])).to eq("Synthetic Hall 205 / NOPE 1")
    end

    it "keeps the text of a part with no room" do
      exam = build(:final_exam, location: "ZZQ 112 / NOPE 5 / Online")

      expect(exam.location_with_names).to eq("Synthetic Hall 112 / NOPE 5 / Online")
    end

    it "keeps the raw location when no room matches" do
      exam = build(:final_exam, location: "NOPE 112")

      expect(exam.location_with_names).to eq("NOPE 112")
    end
  end

  describe ".create_missing_rooms!" do
    it "adds the rooms of a known building only once" do
      building = create(:building, abbreviation: "ZZR", name: "Other Synthetic Hall")
      create(:room, building: building, number: "101")

      expect(described_class.create_missing_rooms!("ZZR 101 / ZZR 2a / NOPE 7 / Online")).to eq(1)
      expect(building.rooms.pluck(:number)).to contain_exactly("101", "2A")
      expect(described_class.create_missing_rooms!("ZZR 2A")).to eq(0)
    end
  end
end
