# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleParserService do
  # Helper to call private methods on the service without needing PDF content or a term
  def service
    described_class.new(pdf_content: "x", term: build_stubbed(:term))
  end

  # ---------------------------------------------------------------------------
  # preprocess_text
  # ---------------------------------------------------------------------------
  describe "#preprocess_text" do
    subject { service.send(:preprocess_text, input) }

    context "strips leading asterisk from amended Spring 2025 rows" do
      let(:input) { "* ARCH1500  01A  27975  27975-27976  Strong  Friday, April 4, 2025  1:00PM-5:00PM  SEE FACULTY" }

      it { is_expected.to start_with("ARCH1500") }
    end

    context "strips 'Date & Time Change' annotation" do
      let(:input) { "COMP1050  01A  30886  Rosenberg  Friday, August 8, 2025  12:45PM-2:45PM  WENTW 306  Date & Time Change" }

      it { is_expected.not_to include("Date & Time Change") }
    end

    context "strips 'Schedule as of' footer" do
      let(:input) { "Some data\nSchedule as of 06/23/25" }

      it { is_expected.not_to include("Schedule as of") }
    end

    context "strips 'UPDATED' prefix before season names" do
      let(:input) { "UPDATED FALL 2025 FINAL EXAM" }

      it { is_expected.to eq("FALL 2025 FINAL EXAM") }
    end
  end

  # ---------------------------------------------------------------------------
  # detect_pdf_format
  # ---------------------------------------------------------------------------
  describe "#detect_pdf_format" do
    subject { service.send(:detect_pdf_format, text) }

    context "with EXAM-DATE header" do
      let(:text) { "COURSE SECTION(S) COMBINED CRNs EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM" }

      it { is_expected.to eq(:fall_2025) }
    end

    context "with COMBINED CRNs header" do
      let(:text) { "COMBINED CRNs something" }

      it { is_expected.to eq(:fall_2025) }
    end

    context "with FINAL DAY header (Fall 2024 / Spring 2025)" do
      let(:text) { "COURSE NUMBER CRN MULTI-SECTION CRNS FINAL DAY FINAL TIME FINAL LOCATION" }

      it { is_expected.to eq(:spring_fall) }
    end

    context "with FINAL DATE header (Summer 2025)" do
      let(:text) { "COURSE NUMBER CRN MULTI-SECTION CRNS FINAL DATE FINAL TIME FINAL LOCATION" }

      it { is_expected.to eq(:spring_fall) }
    end

    context "with MULTI-SECTION CRNS but no FINAL DAY/DATE" do
      let(:text) { "CRN MULTI-SECTION CRNS INSTRUCTOR" }

      it { is_expected.to eq(:spring_fall) }
    end

    context "with unrecognised header" do
      let(:text) { "random content without known markers" }

      it { is_expected.to eq(:unknown) }
    end
  end

  # ---------------------------------------------------------------------------
  # crn_only_line?
  # ---------------------------------------------------------------------------
  describe "#crn_only_line?" do
    subject { service.send(:crn_only_line?, line) }

    context "single CRN" do
      let(:line) { "14611" }

      it { is_expected.to be true }
    end

    context "dash-separated CRN chain" do
      let(:line) { "14612-14613-14614" }

      it { is_expected.to be true }
    end

    context "merged CRN pair (no separator)" do
      let(:line) { "1458814589" }

      it { is_expected.to be true }
    end

    context "mixed merged and normal CRNs" do
      let(:line) { "14583-14584-14585-14586-14587-1458814589-14590-14591-14592-14593-14594" }

      it { is_expected.to be true }
    end

    context "course section code" do
      let(:line) { "ARCH2100-06" }

      it { is_expected.to be false }
    end

    context "section continuation" do
      let(:line) { "13G-15H-17I-19J-21K-23L" }

      it { is_expected.to be false }
    end

    context "time range" do
      let(:line) { "2:00PM-6:00PM" }

      it { is_expected.to be false }
    end

    context "course title" do
      let(:line) { "STUDIO 01" }

      it { is_expected.to be false }
    end
  end

  # ---------------------------------------------------------------------------
  # location_only_line?
  # ---------------------------------------------------------------------------
  describe "#location_only_line?" do
    subject { service.send(:location_only_line?, line) }

    context "standard room" do
      let(:line) { "WENTW 212" }

      it { is_expected.to be true }
    end

    context "room with letter suffix" do
      let(:line) { "CEIS 414A" }

      it { is_expected.to be true }
    end

    context "slash-separated rooms" do
      let(:line) { "ANXSO 002/004" }

      it { is_expected.to be true }
    end

    context "auditorium" do
      let(:line) { "WATSN Auditorium" }

      it { is_expected.to be true }
    end

    context "see faculty" do
      let(:line) { "SEE FACULTY FOR DETAILS" }

      it { is_expected.to be true }
    end

    context "ONLINE" do
      let(:line) { "ONLINE" }

      it { is_expected.to be true }
    end

    context "course title STUDIO 01 (two-digit suffix — not a room)" do
      let(:line) { "STUDIO 01" }

      it { is_expected.to be false }
    end

    context "course title BUILDING MATTERS" do
      let(:line) { "BUILDING MATTERS" }

      it { is_expected.to be false }
    end

    context "instructor name" do
      let(:line) { "Peters, Liu; Stirrat, Rabkin" }

      it { is_expected.to be false }
    end
  end

  # ---------------------------------------------------------------------------
  # extract_date
  # ---------------------------------------------------------------------------
  describe "#extract_date" do
    subject { service.send(:extract_date, line) }

    context "full day/month/year" do
      let(:line) { "Monday, December 8, 2025" }

      it { is_expected.to eq(Date.new(2025, 12, 8)) }
    end

    context "full month (no leading weekday)" do
      let(:line) { "April 14, 2025" }

      it { is_expected.to eq(Date.new(2025, 4, 14)) }
    end

    context "abbreviated month" do
      let(:line) { "Dec 8, 2025" }

      it { is_expected.to eq(Date.new(2025, 12, 8)) }
    end

    context "MM/DD/YYYY" do
      let(:line) { "12/08/2025" }

      it { is_expected.to eq(Date.new(2025, 12, 8)) }
    end

    context "date plus time on same line" do
      let(:line) { "Wednesday, December 10, 2025 10:15AM-12:15PM" }

      it { is_expected.to eq(Date.new(2025, 12, 10)) }
    end

    context "no date" do
      let(:line) { "WENTW 212" }

      it { is_expected.to be_nil }
    end
  end

  # ---------------------------------------------------------------------------
  # extract_time_range
  # ---------------------------------------------------------------------------
  describe "#extract_time_range" do
    subject { service.send(:extract_time_range, line) }

    context "full AM/PM both sides" do
      let(:line) { "8:00AM-10:00AM" }

      it { is_expected.to eq([800, 1000]) }
    end

    context "PM range" do
      let(:line) { "2:00PM-6:00PM" }

      it { is_expected.to eq([1400, 1800]) }
    end

    context "end time without minutes" do
      let(:line) { "9:00AM - 1PM" }

      it { is_expected.to eq([900, 1300]) }
    end

    context "mixed AM/PM" do
      let(:line) { "10:15AM-12:15PM" }

      it { is_expected.to eq([1015, 1215]) }
    end

    context "spaces around dash" do
      let(:line) { "12:45PM - 2:45PM" }

      it { is_expected.to eq([1245, 1445]) }
    end

    context "no time present" do
      let(:line) { "Monday, December 8, 2025" }

      it { is_expected.to eq([nil, nil]) }
    end
  end

  # ---------------------------------------------------------------------------
  # extract_location
  # ---------------------------------------------------------------------------
  describe "#extract_location" do
    subject { service.send(:extract_location, line) }

    context "standard building + room at end of line" do
      let(:line) { "Instructor  Monday, December 8, 2025  2:00PM-6:00PM  WENTW 212" }

      it { is_expected.to eq("WENTW 212") }
    end

    context "room with letter suffix" do
      let(:line) { "CEIS 414A" }

      it { is_expected.to eq("CEIS 414A") }
    end

    context "slash-separated rooms expanded" do
      let(:line) { "ANXSO 002/004" }

      it { is_expected.to eq("ANXSO 002 / ANXSO 004") }
    end

    context "letter-suffix expansion" do
      let(:line) { "CEIS 414A/B" }

      it { is_expected.to eq("CEIS 414A / CEIS 414B") }
    end

    context "auditorium" do
      let(:line) { "WATSN Auditorium" }

      it { is_expected.to eq("WATSN Auditorium") }
    end

    context "see faculty" do
      let(:line) { "Instructor  Thursday  SEE FACULTY" }

      it { is_expected.to eq("SEE FACULTY") }
    end

    context "ONLINE" do
      let(:line) { "ONLINE" }

      it { is_expected.to eq("ONLINE") }
    end

    context "no location" do
      let(:line) { "Peters, Liu; Stirrat, Rabkin; Maloney, Goh" }

      it { is_expected.to be_nil }
    end
  end

  # ---------------------------------------------------------------------------
  # parse_spring_fall_format — unit tests on extracted text
  # ---------------------------------------------------------------------------
  describe "#parse_spring_fall_format" do
    subject(:entries) { service.send(:parse_spring_fall_format, text) }

    context "Summer 2025 row with single CRN" do
      # Column-per-line format as output by pdftotext.
      # The parser anchors on the standalone 5-digit CRN line, then scans
      # forward for date → time → location.
      let(:text) do
        <<~TEXT
          ARCH3200
          04
          PASSIVE & ACTIVE SYSTEMS
          30753
          Joseph, Michaelson
          Thursday, August 7, 2025
          1:00PM-5:00PM
          ANXCN 203
        TEXT
      end

      it "creates one entry with the correct CRN and date" do
        expect(entries.length).to eq(1)
        expect(entries.first[:crn]).to eq(30753)
        expect(entries.first[:date]).to eq(Date.new(2025, 8, 7))
        expect(entries.first[:start_time]).to eq(1300)
        expect(entries.first[:end_time]).to eq(1700)
        expect(entries.first[:location]).to eq("ANXCN 203")
      end
    end

    context "Summer 2025 row with multi-section CRNs" do
      # Each CRN in the combined group gets its own CRN line followed by the
      # dash-separated chain line, then shared date/time/location.
      let(:text) do
        <<~TEXT
          30864
          30864-30862-30863
          Yari, Nasser
          Friday, August 8, 2025
          12:45PM-2:45PM
          BEATT 426
          30862
          30864-30862-30863
          Yari, Nasser
          Friday, August 8, 2025
          12:45PM-2:45PM
          BEATT 426
          30863
          30864-30862-30863
          Yari, Nasser
          Friday, August 8, 2025
          12:45PM-2:45PM
          BEATT 426
        TEXT
      end

      it "creates three entries (one per CRN in the combined group)" do
        expect(entries.pluck(:crn)).to contain_exactly(30864, 30862, 30863)
      end

      it "each entry carries the full combined CRN list" do
        entries.each do |e|
          expect(e[:combined_crns]).to contain_exactly(30864, 30862, 30863)
        end
      end
    end

    context "Fall 2024 — row with date/time expands to all combined CRNs" do
      # Simulate: sections 01A and 03B have no date/time; 05C does.
      # After the fix, all three CRNs should get entries from the 05C row.
      # In column-per-line format, rows without date/time simply have no date
      # line between their CRN and the next CRN.
      let(:text) do
        <<~TEXT
          13823
          13823-13824-13825
          Instructor A
          13824
          13823-13824-13825
          Instructor B
          13825
          13823-13824-13825
          Instructor C
          Monday, December 9, 2024
          8:00AM-12:00PM
          SEE FACULTY
        TEXT
      end

      it "creates entries for all three CRNs" do
        crns = entries.pluck(:crn)
        expect(crns).to include(13823, 13824, 13825)
      end

      it "all entries share the same date and time" do
        dates  = entries.pluck(:date).uniq
        starts = entries.pluck(:start_time).uniq
        expect(dates).to eq([Date.new(2024, 12, 9)])
        expect(starts).to eq([800])
      end
    end

    context "amended Spring 2025 row (asterisk stripped by preprocess_text)" do
      # preprocess_text should have already removed the "*" before this is called,
      # but we test the underlying line parser handles a clean version correctly.
      # Column-per-line format: CRN line, then combined-chain line, then date, time, location.
      let(:text) do
        <<~TEXT
          27975
          27975-27976
          Strong, Ingrid
          Friday, April 4, 2025
          1:00PM-5:00PM
          SEE FACULTY
        TEXT
      end

      it "parses the row correctly" do
        expect(entries.length).to be >= 1
        expect(entries.pluck(:crn)).to include(27975)
        expect(entries.first[:date]).to eq(Date.new(2025, 4, 4))
      end
    end

    context "Summer 2025 format header lines are skipped" do
      # Header lines do not contain standalone 5-digit CRNs so they are
      # naturally ignored by the CRN-anchor state machine.
      let(:text) do
        <<~TEXT
          COURSE NUMBER  SECTION NUMBER  COURSE TITLE  CRN  MULTI-SECTION CRNS  INSTRUCTOR  FINAL DATE  FINAL TIME  FINAL LOCATION
          ARCH3200
          04
          PASSIVE & ACTIVE SYSTEMS
          30753
          Joseph, Michaelson
          Thursday, August 7, 2025
          1:00PM-5:00PM
          ANXCN 203
        TEXT
      end

      it "ignores header lines and parses the data row" do
        expect(entries.length).to eq(1)
        expect(entries.first[:crn]).to eq(30753)
      end
    end

    context "row without date/time is skipped" do
      # A CRN with no date line following it (before the next CRN) produces
      # no entry because the backfill only works within a combined group.
      let(:text) do
        <<~TEXT
          13823
          13823-13824-13825
          Instructor A
        TEXT
      end

      it "produces no entries" do
        expect(entries).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # parse_fall_2025_format — unit tests on extracted text
  # ---------------------------------------------------------------------------
  describe "#parse_fall_2025_format" do
    subject(:entries) { service.send(:parse_fall_2025_format, text) }

    context "simple column block (3-row table)" do
      # Simulates pdftotext column output: CRNs, then dates, then times, then locations
      let(:text) do
        <<~TEXT
          14611
          14612-14613-14614
          14619

          Soufan, Anas
          Mulligan, Dikeos, Peters
          Mak, Anthony

          Wednesday, December 10, 2025
          Thursday, December 11, 2025
          Thursday, December 11, 2025

          12:45PM-2:45PM
          12:45PM-2:45PM
          12:45PM-2:45PM

          WENTW 212
          ANXNO 201
          WENTW 214
        TEXT
      end

      it "creates entries for all CRNs" do
        crns = entries.pluck(:crn)
        expect(crns).to include(14611, 14612, 14613, 14614, 14619)
      end

      it "assigns the correct date to each CRN line" do
        entry_14611 = entries.find { |e| e[:crn] == 14611 }
        entry_14614 = entries.find { |e| e[:crn] == 14614 }
        entry_14619 = entries.find { |e| e[:crn] == 14619 }

        expect(entry_14611[:date]).to eq(Date.new(2025, 12, 10))
        expect(entry_14614[:date]).to eq(Date.new(2025, 12, 11))
        expect(entry_14619[:date]).to eq(Date.new(2025, 12, 11))
      end

      it "assigns the correct location to each CRN line" do
        expect(entries.find { |e| e[:crn] == 14611 }[:location]).to eq("WENTW 212")
        expect(entries.find { |e| e[:crn] == 14612 }[:location]).to eq("ANXNO 201")
        expect(entries.find { |e| e[:crn] == 14619 }[:location]).to eq("WENTW 214")
      end

      it "sets combined_crns correctly for a multi-CRN line" do
        entry_14612 = entries.find { |e| e[:crn] == 14612 }
        expect(entry_14612[:combined_crns]).to contain_exactly(14612, 14613, 14614)
      end
    end

    context "merged CRN pair (no dash separator from pdftotext)" do
      let(:text) do
        <<~TEXT
          14583-14584-14585-14586-14587-1458814589-14590-14591-14592-14593-14594

          Wednesday, December 10, 2025

          12:45PM-2:45PM

          WENTW 212
        TEXT
      end

      it "correctly splits merged CRNs and creates all 12 entries" do
        crns = entries.pluck(:crn)
        expect(crns).to include(14588, 14589)
        expect(crns.length).to eq(12)
      end
    end

    context "header lines are ignored" do
      let(:text) do
        <<~TEXT
          COURSE SECTION(S) COMBINED CRNs EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM
          14611
          Wednesday, December 10, 2025
          12:45PM-2:45PM
          WENTW 212
        TEXT
      end

      it "parses the single entry after stripping the header" do
        expect(entries.length).to eq(1)
        expect(entries.first[:crn]).to eq(14611)
      end
    end

    context "duplicate CRN groups — first date wins" do
      let(:text) do
        <<~TEXT
          14577-14578-14579-14580-14581-14582

          Kim, Carvajal Maldonado, Unaka, Forbush,

          Monday, December 8, 2025

          9:00AM - 1PM

          Gibbons, Vosgueritchian

          Wednesday, December 10, 2025

          10:15AM-12:15PM

          WATSN Auditorium
        TEXT
      end

      it "keeps only the first pairing (Dec 8) for each CRN" do
        expect(entries.pluck(:crn)).to include(14577)
        # All entries should have Dec 8 (the first date block of size 1)
        dec8_entries = entries.select { |e| e[:date] == Date.new(2025, 12, 8) }
        expect(dec8_entries.length).to eq(entries.length)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: detect_pdf_format feeds the right parser
  # ---------------------------------------------------------------------------
  describe "#parse_exam_entries" do
    subject(:entries) { service.send(:parse_exam_entries, text) }

    context "routes spring_fall text to spring_fall parser" do
      # Header triggers :spring_fall detection; data follows in column-per-line format.
      let(:text) do
        <<~TEXT
          COURSE NUMBER  CRN  MULTI-SECTION CRNS  FINAL DAY  FINAL TIME  FINAL LOCATION
          30886
          Rosenberg
          Friday, August 8, 2025
          12:45PM-2:45PM
          WENTW 306
        TEXT
      end

      it "returns parsed entries" do
        expect(entries).not_to be_empty
        expect(entries.first[:crn]).to eq(30886)
      end
    end

    context "routes fall_2025 text to fall_2025 parser" do
      let(:text) do
        <<~TEXT
          EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM
          14611
          Wednesday, December 10, 2025
          12:45PM-2:45PM
          WENTW 212
        TEXT
      end

      it "returns parsed entries" do
        expect(entries).not_to be_empty
        expect(entries.first[:crn]).to eq(14611)
      end
    end
  end
end
