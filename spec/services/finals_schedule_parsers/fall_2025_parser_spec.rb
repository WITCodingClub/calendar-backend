# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleParsers::Fall2025Parser do
  let(:parser) { described_class.new }

  # ---------------------------------------------------------------------------
  # .matches?
  # ---------------------------------------------------------------------------
  describe ".matches?" do
    subject { described_class.matches?(text) }

    context "with COMBINED CRNs header" do
      let(:text) { "COURSE SECTION(S) COMBINED CRNs EXAM-DATE EXAM-TIME-OF-DAY EXAM-ROOM" }

      it { is_expected.to be true }
    end

    context "with Spring/Fall headers" do
      let(:text) { "FINAL DAY FINAL TIME FINAL LOCATION" }

      it { is_expected.to be false }
    end

    context "with Spring 2026 headers (no COMBINED CRNs)" do
      let(:text) { "INSTRUCTOR\nEXAM-DATE\nEXAM-TIME-OF-DAY" }

      it { is_expected.to be false }
    end
  end

  # ---------------------------------------------------------------------------
  # #parse — column block zipper
  # ---------------------------------------------------------------------------
  describe "#parse" do
    subject(:entries) { parser.parse(text) }

    context "simple column block (3-row table)" do
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
        expect(entries.pluck(:crn)).to include(14611, 14612, 14613, 14614, 14619)
      end

      it "assigns the correct date to each CRN line" do
        expect(entries.find { |e| e[:crn] == 14611 }[:date]).to eq(Date.new(2025, 12, 10))
        expect(entries.find { |e| e[:crn] == 14614 }[:date]).to eq(Date.new(2025, 12, 11))
        expect(entries.find { |e| e[:crn] == 14619 }[:date]).to eq(Date.new(2025, 12, 11))
      end

      it "assigns the correct location to each CRN line" do
        expect(entries.find { |e| e[:crn] == 14611 }[:location]).to eq("WENTW 212")
        expect(entries.find { |e| e[:crn] == 14612 }[:location]).to eq("ANXNO 201")
        expect(entries.find { |e| e[:crn] == 14619 }[:location]).to eq("WENTW 214")
      end

      it "sets combined_crns correctly for a multi-CRN line" do
        expect(entries.find { |e| e[:crn] == 14612 }[:combined_crns]).to contain_exactly(14612, 14613, 14614)
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
        expect(entries.pluck(:crn)).to include(14588, 14589)
        expect(entries.length).to eq(12)
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
        expect(entries.select { |e| e[:date] == Date.new(2025, 12, 8) }.length).to eq(entries.length)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------
  describe "#crn_only_line?" do
    subject { parser.send(:crn_only_line?, line) }

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

    context "course section code" do
      let(:line) { "ARCH2100-06" }

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

  describe "#location_only_line?" do
    subject { parser.send(:location_only_line?, line) }

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

    context "instructor name" do
      let(:line) { "Peters, Liu; Stirrat, Rabkin" }

      it { is_expected.to be false }
    end
  end
end
