# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleParserService do
  let(:term) { build_stubbed(:term) }

  def service(content: "x")
    described_class.new(pdf_content: content, term: term)
  end

  # ---------------------------------------------------------------------------
  # Parser detection — routes text to the right parser class
  # ---------------------------------------------------------------------------
  describe "#detect_parser" do
    subject { service.send(:detect_parser, text).class }

    context "Spring 2026 text (INSTRUCTOR + EXAM-DATE as standalone lines)" do
      let(:text) { "CRN\nINSTRUCTOR\nEXAM-DATE\nEXAM-TIME-OF-DAY\nEXAM-ROOM" }

      it { is_expected.to eq(FinalsScheduleParsers::Spring2026Parser) }
    end

    context "Fall 2025 text (COMBINED CRNs)" do
      let(:text) { "COURSE SECTION(S) COMBINED CRNs EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM" }

      it { is_expected.to eq(FinalsScheduleParsers::Fall2025Parser) }
    end

    context "Spring/Fall text (FINAL DAY)" do
      let(:text) { "COURSE NUMBER CRN MULTI-SECTION CRNS FINAL DAY FINAL TIME FINAL LOCATION" }

      it { is_expected.to eq(FinalsScheduleParsers::SpringFallParser) }
    end

    context "Spring/Fall text (FINAL DATE — Summer 2025)" do
      let(:text) { "COURSE NUMBER CRN MULTI-SECTION CRNS FINAL DATE FINAL TIME FINAL LOCATION" }

      it { is_expected.to eq(FinalsScheduleParsers::SpringFallParser) }
    end

    context "unknown format — falls back to parser with most entries" do
      let(:text) { "random content without known markers" }

      it "returns a parser instance" do
        result = service.send(:detect_parser, text)
        expect(result).to be_a(FinalsScheduleParsers::BaseParser)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: detect_parser feeds the right parser end-to-end
  # ---------------------------------------------------------------------------
  describe "parser routing integration" do
    context "routes spring_fall text to SpringFallParser" do
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

      it "produces parsed entries" do
        parser = service.send(:detect_parser, text)
        entries = parser.parse(text)
        expect(entries).not_to be_empty
        expect(entries.first[:crn]).to eq(30886)
      end
    end

    context "routes fall_2025 text to Fall2025Parser" do
      let(:text) do
        <<~TEXT
          EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM COMBINED CRNs
          14611
          Wednesday, December 10, 2025
          12:45PM-2:45PM
          WENTW 212
        TEXT
      end

      it "produces parsed entries" do
        parser = service.send(:detect_parser, text)
        entries = parser.parse(text)
        expect(entries).not_to be_empty
        expect(entries.first[:crn]).to eq(14611)
      end
    end

    context "routes spring_2026 text to Spring2026Parser" do
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
        TEXT
      end

      it "produces parsed entries" do
        parser = service.send(:detect_parser, text)
        entries = parser.parse(text)
        expect(entries).not_to be_empty
        expect(entries.first[:crn]).to eq(29416)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PARSERS constant — correct order and completeness
  # ---------------------------------------------------------------------------
  describe "PARSERS constant" do
    it "lists Spring2026Parser before Fall2025Parser to prevent misdetection" do
      spring_idx = described_class::PARSERS.index(FinalsScheduleParsers::Spring2026Parser)
      fall_idx   = described_class::PARSERS.index(FinalsScheduleParsers::Fall2025Parser)
      expect(spring_idx).to be < fall_idx
    end

    it "includes all three format parsers" do
      expect(described_class::PARSERS).to include(
        FinalsScheduleParsers::Spring2026Parser,
        FinalsScheduleParsers::Fall2025Parser,
        FinalsScheduleParsers::SpringFallParser
      )
    end
  end
end
