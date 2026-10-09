# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::Parsers::Fall2025Parser do
  subject(:parser) { described_class.new }

  let(:text) { file_fixture("finals_schedules/fall_2025.txt").read }

  describe ".matches?" do
    it "matches text with a COMBINED CRNs header" do
      expect(described_class.matches?(text)).to be(true)
    end

    it "does not match other text" do
      expect(described_class.matches?("CRN\nEXAM-DATE")).to be(false)
    end
  end

  describe "#parse" do
    it "expands combined CRNs and expands slash room lists" do
      entries = parser.parse(text)

      expect(entries.map { |e| e[:crn] }).to eq([ 10_001, 10_002, 10_003 ])
      expect(entries.first).to eq(
        crn: 10_001, combined_crns: [ 10_001 ], date: Date.new(2025, 12, 15),
        start_time: 800, end_time: 1000, location: "ZQXB 101"
      )
      expect(entries.last).to include(
        combined_crns: [ 10_002, 10_003 ], date: Date.new(2025, 12, 16),
        start_time: 1300, end_time: 1500, location: "ZQXB 102 / ZQXB 102B"
      )
    end

    it "splits CRNs that the PDF merged without a dash" do
      input = "1000110002\nMonday, December 15, 2025\n8:00 AM - 10:00 AM\nZQXB 101\n"

      expect(parser.parse(input).map { |e| e[:crn] }).to eq([ 10_001, 10_002 ])
    end

    it "keeps an entry whose location block is missing" do
      input = "10001\nMonday, December 15, 2025\n8:00 AM - 10:00 AM\n"

      expect(parser.parse(input).first[:location]).to be_nil
    end

    it "classifies named venues and ONLINE as locations" do
      input = "10001\n10002\nMonday, December 15, 2025\nMonday, December 15, 2025\n" \
              "8:00 AM - 10:00 AM\n1:00 PM - 3:00 PM\nSample Auditorium\nONLINE\n"

      expect(parser.parse(input).map { |e| e[:location] }).to eq([ "Sample Auditorium", "ONLINE" ])
    end

    it "skips a date block with no CRN block of the same size" do
      input = "10001\nMonday, December 15, 2025\nTuesday, December 16, 2025\n" \
              "8:00 AM - 10:00 AM\n1:00 PM - 3:00 PM\n"

      expect(parser.parse(input)).to eq([])
    end

    it "skips a date block with no matching time block" do
      input = "10001\nMonday, December 15, 2025\n"

      expect(parser.parse(input)).to eq([])
    end

    it "skips rows whose CRNs are all below the CRN floor" do
      input = "09999\nMonday, December 15, 2025\n8:00 AM - 10:00 AM\nZQXB 101\n"

      expect(parser.parse(input)).to eq([])
    end

    it "skips a row when the date line has no parsable date" do
      input = "10001\nMonday, Smarch 40, 2025\n8:00 AM - 10:00 AM\n"

      expect(parser.parse(input)).to eq([])
    end

    it "does not treat a time with a location on the same line as a time-only line" do
      input = "10001\nMonday, December 15, 2025\n8:00 AM - 10:00 AM ZQXB 101\n"

      expect(parser.parse(input)).to eq([])
    end

    it "drops a CRN that appears in two rows" do
      input = "10001\n10001\nMonday, December 15, 2025\nTuesday, December 16, 2025\n" \
              "8:00 AM - 10:00 AM\n1:00 PM - 3:00 PM\n"

      expect(parser.parse(input).size).to eq(1)
    end
  end
end
