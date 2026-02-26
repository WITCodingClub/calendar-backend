# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleParsers::Spring2026Parser do
  let(:parser) { described_class.new }

  # ---------------------------------------------------------------------------
  # .matches?
  # ---------------------------------------------------------------------------
  describe ".matches?" do
    subject { described_class.matches?(text) }

    context "with Spring 2026 headers (INSTRUCTOR + EXAM-DATE as standalone lines)" do
      let(:text) { "CRN\nINSTRUCTOR\nEXAM-DATE\nEXAM-TIME-OF-DAY\nEXAM-ROOM" }

      it { is_expected.to be true }
    end

    context "with Fall 2025 headers (COMBINED CRNs present)" do
      let(:text) { "COURSE SECTION(S) COMBINED CRNs EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM" }

      it { is_expected.to be false }
    end

    context "with Spring/Fall headers" do
      let(:text) { "FINAL DAY FINAL TIME FINAL LOCATION" }

      it { is_expected.to be false }
    end

    context "EXAM-DATE inline (not standalone)" do
      # EXAM-DATE appears inside a row, not as its own line — should not match
      let(:text) { "COURSE SECTION CRN EXAM-DATE EXAM-ROOM" }

      it { is_expected.to be false }
    end
  end

  # ---------------------------------------------------------------------------
  # #parse
  # ---------------------------------------------------------------------------
  describe "#parse" do
    subject(:entries) { parser.parse(text) }

    context "single page with no ONLINE courses" do
      let(:text) do
        <<~TEXT
          SPRING 2026 FINAL EXAM SCHEDULE
          COURSE SECTION(S) COURSE TITLE
          ARCH 1500-01A
          STUDIO 02
          ARCH 1500-03B
          STUDIO 02
          ARCH 1500-05C
          STUDIO 02

          CRN
          29416
          29417
          29420

          INSTRUCTOR
          Kim, Lora
          Page, Sarah
          Angieri, Tristan

          EXAM-DATE
          Friday, April 10, 2026
          Friday, April 10, 2026
          Friday, April 10, 2026

          EXAM-TIME-OF-DAY
          10:15 AM - 12:15 PM
          10:15 AM - 12:15 PM
          10:15 AM - 12:15 PM

          EXAM-ROOM
          WENTW 205
          BEATT 421
          DOBBS 003
        TEXT
      end

      it "parses all three entries" do
        expect(entries.length).to eq(3)
        expect(entries.pluck(:crn)).to contain_exactly(29416, 29417, 29420)
      end

      it "extracts date correctly" do
        expect(entries.first[:date]).to eq(Date.new(2026, 4, 10))
      end

      it "extracts space-separated time range correctly" do
        expect(entries.first[:start_time]).to eq(1015)
        expect(entries.first[:end_time]).to eq(1215)
      end

      it "extracts location" do
        expect(entries.find { |e| e[:crn] == 29416 }[:location]).to eq("WENTW 205")
        expect(entries.find { |e| e[:crn] == 29417 }[:location]).to eq("BEATT 421")
      end

      it "sets combined_crns as singleton array (no combined exams in this format)" do
        expect(entries.first[:combined_crns]).to eq([29416])
      end
    end

    context "ONLINE course mixed with regular courses" do
      let(:text) do
        <<~TEXT
          CRN
          29416
          29452
          29465

          INSTRUCTOR
          Kim, Lora
          Peters, Troy, Nolan
          Crossley, Tatjana

          EXAM-DATE
          Friday, April 10, 2026
          ONLINE
          Monday, April 13, 2026

          EXAM-TIME-OF-DAY
          10:15 AM - 12:15 PM
          12:45 PM - 2:45 PM

          EXAM-ROOM
          WENTW 205
          RBSTN 201
        TEXT
      end

      it "skips ONLINE course and returns only courses with real exams" do
        expect(entries.length).to eq(2)
        expect(entries.pluck(:crn)).to contain_exactly(29416, 29465)
      end

      it "does not corrupt time/room alignment after the ONLINE entry" do
        arch_2600 = entries.find { |e| e[:crn] == 29465 }
        expect(arch_2600[:date]).to eq(Date.new(2026, 4, 13))
        expect(arch_2600[:start_time]).to eq(1245)
        expect(arch_2600[:location]).to eq("RBSTN 201")
      end
    end

    context "SEE FACULTY course mixed with regular courses" do
      let(:text) do
        <<~TEXT
          CRN
          29528
          29529
          29530

          INSTRUCTOR
          Cashel-Cordo, William, Jordan
          Cashel-Cordo, William, Jordan
          Cashel-Cordo, William, Jordan

          EXAM-DATE
          Monday, April 13, 2026
          SEE FACULTY
          Monday, April 13, 2026

          EXAM-TIME-OF-DAY
          12:45 PM - 2:45 PM
          12:45 PM - 2:45 PM

          EXAM-ROOM
          BEATT 426
          BEATT 426
        TEXT
      end

      it "skips SEE FACULTY course" do
        expect(entries.length).to eq(2)
        expect(entries.pluck(:crn)).to contain_exactly(29528, 29530)
      end

      it "keeps time/room alignment correct after SEE FACULTY" do
        expect(entries.find { |e| e[:crn] == 29530 }[:location]).to eq("BEATT 426")
      end
    end

    context "multiple ONLINE courses in a row" do
      let(:text) do
        <<~TEXT
          CRN
          28943
          28946
          28949
          28955

          INSTRUCTOR
          Stull, Malinda
          Stull, Malinda
          Stull, Malinda
          Stecher, Nadine

          EXAM-DATE
          ONLINE
          ONLINE
          ONLINE
          Friday, April 10, 2026

          EXAM-TIME-OF-DAY
          3:00 PM - 5:00 PM

          EXAM-ROOM
          BEATT 401
        TEXT
      end

      it "only returns the one non-ONLINE entry" do
        expect(entries.length).to eq(1)
        expect(entries.first[:crn]).to eq(28955)
        expect(entries.first[:start_time]).to eq(1500)
        expect(entries.first[:location]).to eq("BEATT 401")
      end
    end

    context "cross-page noise in EXAM-ROOM section is filtered out" do
      let(:text) do
        <<~TEXT
          CRN
          29416

          INSTRUCTOR
          Kim, Lora

          EXAM-DATE
          Friday, April 10, 2026

          EXAM-TIME-OF-DAY
          10:15 AM - 12:15 PM

          EXAM-ROOM
          WENTW 205
          1 of 17
          SPRING 2026 FINAL EXAM SCHEDULE
          COURSE SECTION(S) COURSE TITLE
          ARCH 1500-03B
          STUDIO 02

          CRN
          29417

          INSTRUCTOR
          Page, Sarah

          EXAM-DATE
          Friday, April 10, 2026

          EXAM-TIME-OF-DAY
          10:15 AM - 12:15 PM

          EXAM-ROOM
          BEATT 421
        TEXT
      end

      it "correctly parses entries across the page boundary" do
        expect(entries.length).to eq(2)
        expect(entries.find { |e| e[:crn] == 29416 }[:location]).to eq("WENTW 205")
        expect(entries.find { |e| e[:crn] == 29417 }[:location]).to eq("BEATT 421")
      end
    end

    context "standalone season+year line in EXAM-ROOM section does not corrupt alignment" do
      # pdftotext sometimes renders the page header as two separate lines:
      # "SPRING 2026" and "FINAL EXAM SCHEDULE" instead of one combined line.
      # "SPRING 2026" alone matches the building+room regex (SPRING=building,
      # 2026=room), which previously inserted a phantom entry into all_rooms and
      # shifted every subsequent CRN to the wrong location (fixes #377).
      let(:text) do
        <<~TEXT
          CRN
          29247
          29250

          INSTRUCTOR
          Doe, Jane
          Smith, Bob

          EXAM-DATE
          Monday, April 13, 2026
          Monday, April 13, 2026

          EXAM-TIME-OF-DAY
          8:00 AM - 10:00 AM
          12:45 PM - 2:45 PM

          EXAM-ROOM
          CEIS 101
          SPRING 2026
          FINAL EXAM SCHEDULE
          WENTW 205
        TEXT
      end

      it "assigns the correct room to each CRN" do
        expect(entries.find { |e| e[:crn] == 29247 }[:location]).to eq("CEIS 101")
        expect(entries.find { |e| e[:crn] == 29250 }[:location]).to eq("WENTW 205")
      end
    end

    context "duplicate CRN — first occurrence wins" do
      let(:text) do
        <<~TEXT
          CRN
          29416
          29416

          INSTRUCTOR
          Kim, Lora
          Kim, Lora

          EXAM-DATE
          Friday, April 10, 2026
          Monday, April 13, 2026

          EXAM-TIME-OF-DAY
          10:15 AM - 12:15 PM
          12:45 PM - 2:45 PM

          EXAM-ROOM
          WENTW 205
          RBSTN 201
        TEXT
      end

      it "returns only one entry for the CRN" do
        expect(entries.length).to eq(1)
        expect(entries.first[:date]).to eq(Date.new(2026, 4, 10))
      end
    end
  end
end
