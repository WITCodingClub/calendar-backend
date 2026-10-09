# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::Parsers::Spring2026Parser do
  subject(:parser) { described_class.new }

  let(:text) { file_fixture("finals_schedules/spring_2026.txt").read }

  describe ".matches?" do
    it "matches the section-header layout" do
      expect(described_class.matches?(text)).to be(true)
    end

    it "does not match a COMBINED CRNs layout" do
      expect(described_class.matches?("#{text}\nCOMBINED CRNs\n")).to be(false)
    end

    it "does not match text with no headers" do
      expect(described_class.matches?("hello")).to be(false)
    end
  end

  describe "#parse" do
    it "builds one entry per CRN with date, time, and room" do
      expect(parser.parse(text)).to eq(
        [
          { crn: 10_001, combined_crns: [ 10_001 ], date: Date.new(2026, 5, 4),
            start_time: 800, end_time: 1000, location: "ZQXB 101" },
          { crn: 10_002, combined_crns: [ 10_002 ], date: Date.new(2026, 5, 5),
            start_time: 1300, end_time: 1500, location: "ZQXB 102" }
        ]
      )
    end

    it "skips CRNs whose date is a non-exam marker" do
      input = <<~TXT
        CRN
        10001
        10002
        EXAM-DATE
        Monday, May 4, 2026
        ONLINE
        EXAM-TIME-OF-DAY
        8:00 AM - 10:00 AM
        EXAM-ROOM
        ZQXB 101
      TXT

      expect(parser.parse(input).map { |e| e[:crn] }).to eq([ 10_001 ])
    end

    it "skips CRNs with no matching date" do
      input = "CRN\n10001\n10002\nEXAM-DATE\nMonday, May 4, 2026\nEXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\n"

      entries = parser.parse(input)

      expect(entries.map { |e| e[:crn] }).to eq([ 10_001 ])
      expect(entries.first[:location]).to be_nil
    end

    it "leaves times nil when the time list is short" do
      input = "CRN\n10001\nEXAM-DATE\nMonday, May 4, 2026\n"

      expect(parser.parse(input).first).to include(start_time: nil, end_time: nil)
    end

    it "ignores lines that are not CRNs, dates, times, or rooms" do
      input = <<~TXT
        CRN
        abc
        123
        10001
        INSTRUCTOR
        Someone
        EXAM-DATE
        garbage
        Monday, May 4, 2026
        EXAM-TIME-OF-DAY
        garbage
        8:00 AM - 10:00 AM
        EXAM-ROOM
        garbage
        ZQXB 101
      TXT

      expect(parser.parse(input).map { |e| e[:crn] }).to eq([ 10_001 ])
    end

    it "pairs dates by position, so a CRN below the floor shifts later rows" do
      input = "CRN\n09999\n10001\nEXAM-DATE\nMonday, May 4, 2026\nTuesday, May 5, 2026\n"

      entries = parser.parse(input)

      expect(entries).to contain_exactly(include(crn: 10_001, date: Date.new(2026, 5, 5)))
    end

    it "drops a repeated CRN" do
      input = "CRN\n10001\n10001\nEXAM-DATE\nMonday, May 4, 2026\nTuesday, May 5, 2026\n"

      expect(parser.parse(input).size).to eq(1)
    end

    it "returns no entries for empty text" do
      expect(parser.parse("")).to eq([])
    end
  end
end
