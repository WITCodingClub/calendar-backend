# frozen_string_literal: true

require "rails_helper"

RSpec.describe External::TwentyFiveLiveService, type: :service do
  fixtures :buildings, :rooms

  class StubbedService < External::TwentyFiveLiveService
    def initialize(responses = {})
      @responses = responses
    end

    def fetch(endpoint)
      @responses[endpoint] || {}
    end
  end

  WENTWORTH_SPACE = {
    "space_id"      => 199,
    "space_name"    => "WT 310",
    "formal_name"   => "Wentworth Hall 310",
    "building_id"   => 22,
    "building_name" => "Wentworth Hall"
  }.freeze

  def spaces_payload(spaces)
    { "spaces" => { "space" => spaces } }
  end

  describe "#sync_spaces" do
    it "associates 25Live IDs and formal names to room and building" do
      StubbedService.new("spaces" => spaces_payload([ WENTWORTH_SPACE ])).send(:sync_spaces)

      room     = rooms(:wt_310).reload
      building = buildings(:WT).reload

      expect(room.twenty_five_live_id).to eq(199)
      expect(room.formal_name).to eq("Wentworth Hall 310")
      expect(building.twenty_five_live_id).to eq(22)
      expect(building.formal_name).to eq("Wentworth Hall")
    end

    it "skips space when abbreviation doesn't match any building" do
      payload = spaces_payload([
        { "space_id" => 777, "space_name" => "NOPE 100", "building_id" => 99, "building_name" => "Unknown" }
      ])

      StubbedService.new("spaces" => payload).send(:sync_spaces)

      expect(rooms(:comp_100).reload.twenty_five_live_id).to be_nil
    end

    it "skips space when room number doesn't match" do
      payload = spaces_payload([
        { "space_id" => 888, "space_name" => "COMP 999", "building_id" => 55, "building_name" => "Computing Center" }
      ])

      StubbedService.new("spaces" => payload).send(:sync_spaces)

      expect(rooms(:comp_100).reload.twenty_five_live_id).to be_nil
    end

    it "skips space_name with no room portion" do
      payload = spaces_payload([
        { "space_id" => 213, "space_name" => "AwayGame", "building_id" => 0, "building_name" => "" }
      ])

      StubbedService.new("spaces" => payload).send(:sync_spaces)

      expect(rooms(:wt_310).reload.twenty_five_live_id).to be_nil
    end

    it "does not overwrite existing twenty_five_live_id on room" do
      rooms(:wt_310).update!(twenty_five_live_id: 1, formal_name: "Original")

      StubbedService.new("spaces" => spaces_payload([ WENTWORTH_SPACE ])).send(:sync_spaces)

      room = rooms(:wt_310).reload
      expect(room.twenty_five_live_id).to eq(1)
      expect(room.formal_name).to eq("Original")
    end

    it "skips TBD buildings" do
      buildings(:WT).update!(name: "To Be Determined", abbreviation: "TBD")

      payload = spaces_payload([
        { "space_id" => 999, "space_name" => "TBD 310", "building_id" => 22, "building_name" => "TBD" }
      ])

      StubbedService.new("spaces" => payload).send(:sync_spaces)

      expect(rooms(:wt_310).reload.twenty_five_live_id).to be_nil
    end

    it "handles r25: prefixed keys" do
      payload = {
        "r25:spaces" => {
          "r25:space" => [
            {
              "r25:space_id"      => 111,
              "r25:space_name"    => "COMP 100",
              "r25:formal_name"   => "Computing Center 100",
              "r25:building_id"   => 22,
              "r25:building_name" => "Computing Center"
            }
          ]
        }
      }

      StubbedService.new("spaces" => payload).send(:sync_spaces)

      room = rooms(:comp_100).reload
      expect(room.twenty_five_live_id).to eq(111)
      expect(room.formal_name).to eq("Computing Center 100")
    end
  end
end
