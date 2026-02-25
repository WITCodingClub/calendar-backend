# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleParsers::SpringFallParser do
  let(:parser) { described_class.new }

  # ---------------------------------------------------------------------------
  # .matches?
  # ---------------------------------------------------------------------------
  describe ".matches?" do
    subject { described_class.matches?(text) }

    context "with FINAL DAY header (Fall 2024 / Spring 2025)" do
      let(:text) { "COURSE NUMBER CRN MULTI-SECTION CRNS FINAL DAY FINAL TIME FINAL LOCATION" }

      it { is_expected.to be true }
    end

    context "with FINAL DATE header (Summer 2025)" do
      let(:text) { "COURSE NUMBER CRN MULTI-SECTION CRNS FINAL DATE FINAL TIME FINAL LOCATION" }

      it { is_expected.to be true }
    end

    context "with MULTI-SECTION CRNS but no FINAL DAY/DATE" do
      let(:text) { "CRN MULTI-SECTION CRNS INSTRUCTOR" }

      it { is_expected.to be true }
    end

    context "with Fall 2025 headers" do
      let(:text) { "COMBINED CRNs EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM" }

      it { is_expected.to be false }
    end

    context "with Spring 2026 headers" do
      let(:text) { "INSTRUCTOR\nEXAM-DATE\nEXAM-TIME-OF-DAY" }

      it { is_expected.to be false }
    end
  end

  # ---------------------------------------------------------------------------
  # #parse
  # ---------------------------------------------------------------------------
  describe "#parse" do
    subject(:entries) { parser.parse(text) }

    context "Summer 2025 row with single CRN" do
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

    context "Fall 2024 — row with date/time backfills to all combined CRNs" do
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
        expect(entries.pluck(:crn)).to include(13823, 13824, 13825)
      end

      it "all entries share the same date and time" do
        expect(entries.pluck(:date).uniq).to eq([Date.new(2024, 12, 9)])
        expect(entries.pluck(:start_time).uniq).to eq([800])
      end
    end

    context "amended Spring 2025 row (asterisk stripped by preprocess_text)" do
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

    context "header lines are naturally skipped (no standalone 5-digit CRN)" do
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

    context "row without date/time is excluded" do
      let(:text) do
        <<~TEXT
          13823
          13823-13824-13825
          Instructor A
        TEXT
      end

      it { is_expected.to be_empty }
    end
  end
end
