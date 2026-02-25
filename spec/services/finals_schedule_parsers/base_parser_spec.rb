# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsScheduleParsers::BaseParser do
  # Use a minimal concrete subclass so we can call private helpers directly.
  let(:parser) { Class.new(described_class).new }

  # ---------------------------------------------------------------------------
  # preprocess_text
  # ---------------------------------------------------------------------------
  describe "#preprocess_text" do
    subject { parser.send(:preprocess_text, input) }

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
  # extract_date
  # ---------------------------------------------------------------------------
  describe "#extract_date" do
    subject { parser.send(:extract_date, line) }

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

    context "Spring 2026 long-form date" do
      let(:line) { "Friday, April 10, 2026" }

      it { is_expected.to eq(Date.new(2026, 4, 10)) }
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
    subject { parser.send(:extract_time_range, line) }

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

    context "spaces around dash (Spring 2026 format)" do
      let(:line) { "10:15 AM - 12:15 PM" }

      it { is_expected.to eq([1015, 1215]) }
    end

    context "evening slot with space-separated AM/PM" do
      let(:line) { "5:15 PM - 7:15 PM" }

      it { is_expected.to eq([1715, 1915]) }
    end

    context "early morning slot" do
      let(:line) { "8:00 AM - 10:00 AM" }

      it { is_expected.to eq([800, 1000]) }
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
    subject { parser.send(:extract_location, line) }

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
  # no_exam_entry?
  # ---------------------------------------------------------------------------
  describe "#no_exam_entry?" do
    subject { parser.send(:no_exam_entry?, line) }

    context "ONLINE" do
      let(:line) { "ONLINE" }

      it { is_expected.to be true }
    end

    context "SEE FACULTY" do
      let(:line) { "SEE FACULTY" }

      it { is_expected.to be true }
    end

    context "TBA" do
      let(:line) { "TBA" }

      it { is_expected.to be true }
    end

    context "VIRTUAL" do
      let(:line) { "VIRTUAL" }

      it { is_expected.to be true }
    end

    context "regular date" do
      let(:line) { "Friday, April 10, 2026" }

      it { is_expected.to be false }
    end
  end
end
