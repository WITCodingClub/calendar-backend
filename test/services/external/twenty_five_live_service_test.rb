# frozen_string_literal: true

require "test_helper"

class External::TwentyFiveLiveServiceTest < ActiveSupport::TestCase
  fixtures :buildings, :rooms

  # Test double that overrides fetch to return controlled data per endpoint
  class StubbedService < External::TwentyFiveLiveService
    def initialize(responses = {})
      @responses = responses
    end

    def fetch(endpoint)
      @responses[endpoint] || {}
    end
  end

  # Real API format: space_name = "ABBREV ROOM_NUMBER"
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

  test "sync_spaces associates 25Live IDs and formal names to room and building" do
    StubbedService.new("spaces" => spaces_payload([WENTWORTH_SPACE])).send(:sync_spaces)

    room     = rooms(:wt_310).reload
    building = buildings(:WT).reload

    assert_equal 199, room.twenty_five_live_id
    assert_equal "Wentworth Hall 310", room.formal_name
    assert_equal 22, building.twenty_five_live_id
    assert_equal "Wentworth Hall", building.formal_name
  end

  test "sync_spaces skips space when abbreviation doesn't match any building" do
    payload = spaces_payload([
      { "space_id" => 777, "space_name" => "NOPE 100", "building_id" => 99, "building_name" => "Unknown" }
    ])

    StubbedService.new("spaces" => payload).send(:sync_spaces)

    assert_nil rooms(:comp_100).reload.twenty_five_live_id
  end

  test "sync_spaces skips space when room number doesn't match" do
    payload = spaces_payload([
      { "space_id" => 888, "space_name" => "COMP 999", "building_id" => 55, "building_name" => "Computing Center" }
    ])

    StubbedService.new("spaces" => payload).send(:sync_spaces)

    assert_nil rooms(:comp_100).reload.twenty_five_live_id
  end

  test "sync_spaces skips space_name with no room portion" do
    payload = spaces_payload([
      { "space_id" => 213, "space_name" => "AwayGame", "building_id" => 0, "building_name" => "" }
    ])

    StubbedService.new("spaces" => payload).send(:sync_spaces)

    assert_nil rooms(:wt_310).reload.twenty_five_live_id
  end

  test "sync_spaces does not overwrite existing twenty_five_live_id on room" do
    rooms(:wt_310).update!(twenty_five_live_id: 1, formal_name: "Original")

    StubbedService.new("spaces" => spaces_payload([WENTWORTH_SPACE])).send(:sync_spaces)

    room = rooms(:wt_310).reload
    assert_equal 1, room.twenty_five_live_id
    assert_equal "Original", room.formal_name
  end

  test "sync_spaces skips TBD buildings" do
    buildings(:WT).update!(name: "To Be Determined", abbreviation: "TBD")

    payload = spaces_payload([
      { "space_id" => 999, "space_name" => "TBD 310", "building_id" => 22, "building_name" => "TBD" }
    ])

    StubbedService.new("spaces" => payload).send(:sync_spaces)

    assert_nil rooms(:wt_310).reload.twenty_five_live_id
  end

  test "sync_spaces handles r25: prefixed keys" do
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
    assert_equal 111, room.twenty_five_live_id
    assert_equal "Computing Center 100", room.formal_name
  end
end
