# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::Parsers::SpringFallParser do
  subject(:parser) { described_class.new }

  let(:text) { file_fixture("finals_schedules/spring_fall.txt").read }

  describe ".matches?" do
    it "matches FINAL DAY and FINAL DATE headers" do
      expect(described_class.matches?("FINAL DAY")).to be(true)
      expect(described_class.matches?("Final  Date")).to be(true)
    end

    it "matches MULTI-SECTION CRNS" do
      expect(described_class.matches?("multi-section crns")).to be(true)
    end

    it "does not match other text" do
      expect(described_class.matches?("CRN\nEXAM-DATE")).to be(false)
    end
  end

  describe "#parse" do
    it "reads dates, times, locations, and combined CRNs" do
      entries = parser.parse(text)

      expect(entries.first).to eq(
        crn: 10_001, combined_crns: [ 10_001, 10_002 ], date: Date.new(2025, 12, 15),
        start_time: 800, end_time: 1000, location: "ZQXB 101"
      )
    end

    it "copies the schedule from a sibling in the same combined group" do
      second = parser.parse(text).find { |e| e[:crn] == 10_002 }

      expect(second).to include(
        combined_crns: [ 10_001, 10_002 ], date: Date.new(2025, 12, 15),
        start_time: 800, end_time: 1000, location: "ZQXB 101"
      )
    end

    it "keeps a time with no location line after it" do
      third = parser.parse(text).find { |e| e[:crn] == 10_003 }

      expect(third).to include(start_time: 1300, end_time: 1500, location: nil)
    end

    it "drops a CRN with no date and no sibling to copy from" do
      input = "FINAL DAY\n10005\n"

      expect(parser.parse(input)).to eq([])
    end

    it "drops a CRN that has a date but no time" do
      input = "10001\nMonday, December 15, 2025\n"

      expect(parser.parse(input)).to eq([])
    end

    it "stops reading a record at the next CRN" do
      input = "10001\n10002\nMonday, December 15, 2025\n8:00 AM - 10:00 AM\n"

      expect(parser.parse(input).map { |e| e[:crn] }).to eq([ 10_002 ])
    end

    it "skips lines before a date and between a date and a time" do
      input = "10001\nnoise\nMonday, December 15, 2025\nmore noise\n8:00 AM - 10:00 AM\nZQXB 101\n"

      expect(parser.parse(input).first).to include(date: Date.new(2025, 12, 15), location: "ZQXB 101")
    end

    it "keeps an own location instead of the sibling's" do
      input = <<~TXT
        10001
        10001-10002
        Monday, December 15, 2025
        8:00 AM - 10:00 AM
        ZQXB 101
        10002
        10001-10002
      TXT

      expect(parser.parse(input).map { |e| e[:location] }).to eq([ "ZQXB 101", "ZQXB 101" ])
    end
  end
end
