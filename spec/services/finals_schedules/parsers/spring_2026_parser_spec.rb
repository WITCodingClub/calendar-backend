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

    it "skips a page when the date column is short" do
      input = "CRN\n10001\n10002\nEXAM-DATE\nMonday, May 4, 2026\nEXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\n"

      expect(parser.parse(input)).to eq([])
      expect(parser.warnings).to contain_exactly(a_string_including("2 CRNs but 1 exam dates"))
    end

    it "skips a page when the time column is short" do
      input = "CRN\n10001\nEXAM-DATE\nMonday, May 4, 2026\n"

      expect(parser.parse(input)).to eq([])
      expect(parser.warnings).to contain_exactly(a_string_including("1 dated exams but 0 exam times"))
    end

    it "keeps the exams with no location when the room column is short" do
      input = "CRN\n10001\nEXAM-DATE\nMonday, May 4, 2026\nEXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\n"

      expect(parser.parse(input)).to contain_exactly(include(crn: 10_001, start_time: 800, location: nil))
      expect(parser.warnings).to contain_exactly(a_string_including("locations left blank"))
    end

    it "pairs times and rooms with the dated rows only" do
      input = <<~TXT
        CRN
        10001
        10002
        10003
        EXAM-DATE
        Monday, May 4, 2026
        ONLINE
        Tuesday, May 5, 2026
        EXAM-TIME-OF-DAY
        8:00 AM - 10:00 AM
        1:00 PM - 3:00 PM
        EXAM-ROOM
        ZQXB 101
        ZQXB 402A
      TXT

      expect(parser.parse(input).map { |e| e.slice(:crn, :start_time, :location) }).to eq([
        { crn: 10_001, start_time: 800, location: "ZQXB 101" },
        { crn: 10_003, start_time: 1300, location: "ZQXB 402A" }
      ])
    end

    it "pairs times and rooms by row when every row has a value" do
      input = <<~TXT
        CRN
        10001
        10002
        EXAM-DATE
        ONLINE
        Tuesday, May 5, 2026
        EXAM-TIME-OF-DAY
        8:00 AM - 10:00 AM
        1:00 PM - 3:00 PM
        EXAM-ROOM
        ONLINE
        ZQXB 101
      TXT

      expect(parser.parse(input).map { |e| e.slice(:crn, :start_time, :location) }).to eq([
        { crn: 10_002, start_time: 1300, location: "ZQXB 101" }
      ])
    end

    it "skips only the page where a time did not parse" do
      bad_page = "CRN\n10001\n10002\nEXAM-DATE\nMonday, May 4, 2026\nTuesday, May 5, 2026\n" \
                 "EXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\nafter lunch\nEXAM-ROOM\nZQXB 101\nZQXB 102\n"
      good_page = "CRN\n10003\nEXAM-DATE\nWednesday, May 6, 2026\nEXAM-TIME-OF-DAY\n3:00 PM - 5:00 PM\n" \
                  "EXAM-ROOM\nZQXB 103\n"

      entries = parser.parse(bad_page + good_page)

      expect(entries.map { |e| e.slice(:crn, :start_time, :location) }).to eq([
        { crn: 10_003, start_time: 1500, location: "ZQXB 103" }
      ])
      expect(parser.warnings).to contain_exactly(a_string_including("page 1", "page skipped"))
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

    it "skips a CRN below the floor and keeps the next row's own date" do
      input = "CRN\n09999\n10001\nEXAM-DATE\nMonday, May 4, 2026\nTuesday, May 5, 2026\n" \
              "EXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\n1:00 PM - 3:00 PM\n"

      entries = parser.parse(input)

      expect(entries).to contain_exactly(include(crn: 10_001, date: Date.new(2026, 5, 5)))
    end

    it "drops a repeated CRN" do
      input = "CRN\n10001\n10001\nEXAM-DATE\nMonday, May 4, 2026\nTuesday, May 5, 2026\n" \
              "EXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\n1:00 PM - 3:00 PM\n"

      expect(parser.parse(input).size).to eq(1)
    end

    it "returns no entries for empty text" do
      expect(parser.parse("")).to eq([])
    end
  end
end
