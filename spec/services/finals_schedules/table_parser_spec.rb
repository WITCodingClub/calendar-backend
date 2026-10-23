# frozen_string_literal: true

require "rails_helper"

# Each fixture copies the layout of one real WIT finals PDF, with made-up data.
RSpec.describe FinalsSchedules::TableParser do
  subject(:parser) { described_class.new }

  def parse(name)
    parser.parse(file_fixture("finals_schedules/#{name}.txt").read).index_by { |e| e[:crn] }
  end

  def row(crn, date, time, room = "")
    format("%-15s%-33s%-8s%-31s%-30s%-21s%s", "ZQXA1000-01", "SAMPLE STUDIO", crn, "Doe, Jane", date, time, room).rstrip
  end

  describe "Fall 2022 layout" do
    let(:entries) { parse("fall_2022") }

    it "reads a row with the CRN first and a tag after the room" do
      expect(entries[10_001]).to eq(
        crn: 10_001, combined_crns: [ 10_001 ], date: Date.new(2022, 12, 12),
        start_time: 1500, end_time: 1700, location: "ZQXB 201"
      )
    end

    it "labels a virtual exam and keeps a named room" do
      expect(entries[10_002][:location]).to eq("Virtual")
      expect(entries[10_003]).to include(location: "Sample Aud.", start_time: 1800, end_time: 2000)
    end
  end

  describe "Fall 2023 layout" do
    let(:entries) { parse("fall_2023") }

    it "adds a space between the building and the room" do
      expect(entries[10_011][:location]).to eq("ZQXB 102")
      expect(entries[10_012][:location]).to eq("525ZQ 114")
    end

    it "skips an online row with no warning" do
      expect(entries.keys).to eq([ 10_011, 10_012 ])
      expect(parser.warnings).to eq([])
    end
  end

  describe "Summer 2024 layout" do
    let(:entries) { parse("summer_2024") }

    it "reads capital weekdays and months and the multi-section CRNs" do
      expect(entries[10_022]).to include(date: Date.new(2024, 8, 12), start_time: 1245, combined_crns: [ 10_023, 10_022 ])
      expect(entries[10_023][:combined_crns]).to eq([ 10_023, 10_022 ])
      expect(entries[10_021][:combined_crns]).to eq([ 10_021 ])
    end

    it "gives a #N/A room no location" do
      expect(entries[10_024][:location]).to be_nil
    end
  end

  describe "Spring 2025 layout" do
    let(:entries) { parse("spring_2025") }

    it "reads rows with an update mark and labels a SEE FACULTY room" do
      expect(entries[10_031]).to include(date: Date.new(2025, 4, 4), start_time: 1300, end_time: 1700,
                                         location: "See Faculty", combined_crns: [ 10_031, 10_032 ])
    end

    it "expands a room list" do
      expect(entries[10_033]).to include(location: "ZQXB 414A / ZQXB 414B", combined_crns: [ 10_033 ])
      expect(entries[10_035][:location]).to eq("ZQXB 002 / ZQXB 004")
    end

    it "skips a SEE FACULTY row with no date and gives no warning" do
      expect(entries).not_to have_key(10_034)
      expect(parser.warnings).to eq([])
    end
  end

  describe "Fall 2025 layout" do
    let(:entries) { parse("fall_2025") }

    it "makes one entry for each CRN in a chain" do
      expect(entries.values_at(10_041, 10_042)).to all(include(combined_crns: [ 10_041, 10_042 ], start_time: 1400, end_time: 1800,
                                                               location: "ZQXB Auditorium"))
    end

    it "reads an end time with no minutes" do
      expect(entries[10_043]).to include(start_time: 900, end_time: 1300)
    end

    it "takes the CRNs of a tall row from the lines around its date" do
      expect(entries[10_045]).to include(combined_crns: [ 10_045, 10_046, 10_047, 10_048 ],
                                         date: Date.new(2025, 12, 10), location: "ZQXB 201")
      expect(entries.keys).to include(10_046, 10_047, 10_048)
    end

    it "skips a row with no date and warns about a row with no CRN" do
      expect(entries).not_to have_key(10_049)
      expect(entries[10_051]).to include(location: "ZQXB 214")
      expect(parser.warnings).to contain_exactly(a_string_including("Row has no CRN: ZQXF1000-01A-03B"))
    end
  end

  describe "Spring 2026 layout" do
    let(:entries) { parse("spring_2026") }

    it "reads a plain row table" do
      expect(entries[10_062]).to eq(
        crn: 10_062, combined_crns: [ 10_062 ], date: Date.new(2026, 4, 9),
        start_time: 1500, end_time: 1700, location: "ZQXB 419"
      )
    end
  end

  describe "Fall 2026 layout" do
    let(:entries) { parse("fall_2026") }

    it "keeps a building with no room and drops a repeated CRN" do
      expect(entries.keys).to eq([ 10_071, 10_072, 10_073, 10_074, 10_075, 10_076 ])
      expect(entries[10_071][:location]).to eq("ZQXB")
    end

    it "uses the year most rows use when the weekday matches it" do
      expect(entries[10_072][:date]).to eq(Date.new(2026, 12, 11))
      expect(parser.warnings).to contain_exactly(
        "Finals PDF: 1 rows had a year other than 2026; used 2026 for CRNs 10072"
      )
    end

    it "joins a room that wraps around its row, also across a page break" do
      expect(entries[10_074][:location]).to eq("ZQXN/ZQXS CRIT")
      expect(entries[10_075][:location]).to eq("ZQXN/ZQXS CRIT")
    end

    it "reads a time with no space before PM" do
      expect(entries[10_076]).to include(start_time: 1500, end_time: 1800, location: "ZQXN CRIT RM")
    end
  end

  describe "rows next to each other" do
    def line(section, crns, date = "", time = "", room = "")
      format("%-35s%-33s%-39s%-45s%-31s%-19s%s", section, "SAMPLE", crns, "", date, time, room).rstrip
    end

    it "does not give a row with no CRN the CRNs of a row with no date" do
      text = [
        line("ZQXA2100-01", "10049-10050", "", "", "TO BE ANNOUNCED"),
        line("ZQXF1000-01", "FILL IN", "Tuesday, December 9, 2025", "1:00PM-4:00PM", "ZQXB AUD")
      ].join("\n")

      expect(parser.parse(text)).to eq([])
      expect(parser.warnings).to contain_exactly(a_string_including("Row has no CRN"),
                                                 a_string_including("Row has no exam date and time"))
    end

    it "gives an open chain to the tall row below it, not to a row with no CRN above it" do
      text = [
        line("ZQXF1000-01", "FILL IN", "Tuesday, December 9, 2025", "1:00PM-4:00PM", "ZQXB AUD"),
        line("ZQXA1200-01-", "10045-10046-"),
        line("", "", "Wednesday, December 10, 2025", "10:15AM-12:15PM", "ZQXB 201"),
        line("05C", "10047-10048")
      ].join("\n")

      expect(parser.parse(text)).to all(include(date: Date.new(2025, 12, 10), combined_crns: [ 10_045, 10_046, 10_047, 10_048 ]))
      expect(parser.parse(text).size).to eq(4)
    end

    it "continues a chain that wraps from a row that has CRNs" do
      text = [
        row("10031", "Friday, April 4, 2025", "1:00PM-5:00PM", "ZQXB 101").sub("10031  ", "10031-  "),
        format("%-48s%s", "", "10033")
      ].join("\n")

      expect(parser.parse(text)).to contain_exactly(include(crn: 10_031, combined_crns: [ 10_031, 10_033 ]),
                                                    include(crn: 10_033, combined_crns: [ 10_031, 10_033 ]))
      expect(parser.warnings).to eq([])
    end

    it "does not take a tag as the room" do
      text = row("10001", "Monday, December 14, 2026", "8:00 AM - 10:00 AM", "                    COMBINED FINAL")

      expect(parser.parse(text)).to contain_exactly(include(location: nil))
    end

    it "does not take the lower part of a wrapped room for the next row" do
      text = [
        format("%140s%s", "", "ZQXN/ZQXS"),
        row("10001", "Tuesday, December 08, 2026", "1:00 PM - 5:00 PM"),
        format("%144s%s", "", "CRIT"),
        row("10002", "Tuesday, December 08, 2026", "1:00 PM - 5:00 PM")
      ].join("\n")

      expect(parser.parse(text).map { |e| e[:location] }).to eq([ "ZQXN/ZQXS CRIT", nil ])
    end

    it "warns when a CRN has a second row with other data" do
      text = [
        row("10001", "Monday, December 14, 2026", "8:00 AM - 10:00 AM", "ZQXB 101"),
        row("10001", "Tuesday, December 15, 2026", "8:00 AM - 10:00 AM", "ZQXB 102")
      ].join("\n")

      expect(parser.parse(text)).to contain_exactly(include(crn: 10_001, location: "ZQXB 101"))
      expect(parser.warnings).to contain_exactly(a_string_including("CRN 10001 has more than one row"))
    end
  end

  describe "dates" do
    it "keeps the printed year when the weekday does not match the common year" do
      text = [
        row("10001", "Monday, December 14, 2026", "8:00 AM - 10:00 AM"),
        row("10002", "Monday, December 14, 2026", "8:00 AM - 10:00 AM"),
        row("10003", "Tuesday, January 05, 2027", "8:00 AM - 10:00 AM")
      ].join("\n")

      expect(parser.parse(text).last).to include(crn: 10_003, date: Date.new(2027, 1, 5))
      expect(parser.warnings).to eq([])
    end

    it "skips a row whose weekday matches no year" do
      expect(parser.parse(row("10001", "Sunday, December 14, 2026", "8:00 AM - 10:00 AM"))).to eq([])
      expect(parser.warnings).to contain_exactly(a_string_including("CRN 10001", "row skipped"))
    end

    it "skips a row with an impossible date" do
      expect(parser.parse(row("10001", "Monday, February 30, 2026", "8:00 AM - 10:00 AM"))).to eq([])
      expect(parser.warnings).to contain_exactly(a_string_including("CRN 10001", "row skipped"))
    end
  end

  describe "other rows" do
    it "warns about a CRN row with no date and time" do
      expect(parser.parse(row("10001", "December 14", "8:00 AM - 10:00 AM"))).to eq([])
      expect(parser.warnings).to contain_exactly(a_string_including("Row has no exam date and time: ZQXA1000-01"))
    end

    it "labels each no-exam marker in the room cell" do
      text = [
        row("10001", "Monday, December 14, 2026", "8:00 AM - 10:00 AM", "SEE FACULTY FOR DETAILS"),
        row("10002", "Monday, December 14, 2026", "8:00 AM - 10:00 AM", "ONLINE"),
        row("10003", "Monday, December 14, 2026", "8:00 AM - 10:00 AM", "TBA")
      ].join("\n")

      expect(parser.parse(text).map { |e| e[:location] }).to eq([ "See Faculty", "Online", "TBA" ])
    end

    it "does not take a wrapped instructor as the room" do
      text = [
        "#{' ' * 56}Moe, Max;",
        row("10001", "Monday, December 14, 2026", "8:00 AM - 10:00 AM"),
        "#{' ' * 56}Kai"
      ].join("\n")

      expect(parser.parse(text)).to contain_exactly(include(location: nil))
    end

    it "returns no entries for empty text" do
      expect(parser.parse("")).to eq([])
      expect(parser.parse(nil)).to eq([])
    end
  end
end
