# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::Parsers::BaseParser do
  # A tiny subclass exposes the protected helpers through #parse-free public wrappers.
  let(:helper_class) do
    Class.new(described_class) do
      %i[preprocess_text extract_date extract_time_range extract_location
         expand_room_list no_exam_entry? convert_to_24h].each do |name|
        define_method(:"call_#{name}") { |*args| send(name, *args) }
      end
    end
  end
  let(:helper) { helper_class.new }

  describe "abstract interface" do
    it "requires subclasses to implement .matches?" do
      expect { described_class.matches?("x") }.to raise_error(NotImplementedError, /matches\?/)
    end

    it "requires subclasses to implement #parse" do
      expect { described_class.new.parse("x") }.to raise_error(NotImplementedError, /parse/)
    end
  end

  describe "text clean-up" do
    it "strips bullets, change flags, headers, and UPDATED prefixes" do
      text = "* 10001\nDate & Time Change\nFINAL SCHEDULE INFORMATION for all\nSchedule as of 12/01/2025\nUPDATED FALL 2025\n"
      result = helper.call_preprocess_text(text)

      expect(result).to include("10001")
      expect(result).not_to match(/Date & Time Change|FINAL SCHEDULE INFORMATION|Schedule as of|UPDATED/)
      expect(result).to include("FALL 2025")
    end
  end

  describe "date extraction" do
    it "reads numeric dates" do
      expect(helper.call_extract_date("Exam 12/15/2025")).to eq(Date.new(2025, 12, 15))
    end

    it "reads full month names" do
      expect(helper.call_extract_date("Monday, December 15, 2025")).to eq(Date.new(2025, 12, 15))
    end

    it "reads abbreviated month names" do
      expect(helper.call_extract_date("Dec 5 2025")).to eq(Date.new(2025, 12, 5))
    end

    it "returns nil when there is no date" do
      expect(helper.call_extract_date("no date here")).to be_nil
    end

    it "returns nil and warns on an impossible date" do
      allow(Rails.logger).to receive(:warn)

      expect(helper.call_extract_date("13/45/2025")).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/Failed to parse date/)
    end
  end

  describe "time range extraction" do
    it "reads a full AM/PM range" do
      expect(helper.call_extract_time_range("8:00 AM - 10:30 AM")).to eq([ 800, 1030 ])
    end

    it "converts 12 PM to noon and 12 AM to midnight" do
      expect(helper.call_extract_time_range("12:00 PM - 2:00 PM")).to eq([ 1200, 1400 ])
      expect(helper.call_extract_time_range("12:00 AM - 1:00 AM")).to eq([ 0, 100 ])
    end

    it "reads a range whose end has no minutes" do
      expect(helper.call_extract_time_range("1:30 PM - 3 PM")).to eq([ 1330, 1500 ])
    end

    it "reads a 24-hour range" do
      expect(helper.call_extract_time_range("0800 - 1000")).to eq([ 800, 1000 ])
    end

    it "returns nils when there is no range" do
      expect(helper.call_extract_time_range("TBA")).to eq([ nil, nil ])
    end
  end

  describe "location extraction" do
    it "reads a building and room" do
      expect(helper.call_extract_location("ZQXB 101")).to eq("ZQXB 101")
    end

    it "reads an auditorium room" do
      expect(helper.call_extract_location("ZQXB AUD")).to eq("ZQXB AUD")
    end

    it "expands a slash room list that shares a number" do
      expect(helper.call_extract_location("ZQXB 102/B")).to eq("ZQXB 102 / ZQXB 102B")
    end

    it "expands a slash room list of separate numbers" do
      expect(helper.call_extract_location("ZQXB 101/202")).to eq("ZQXB 101 / ZQXB 202")
    end

    it "reads a named venue" do
      expect(helper.call_extract_location("Sample Auditorium")).to eq("Sample Auditorium")
    end

    it "reads ONLINE, TBA, and VIRTUAL in upper case" do
      expect(helper.call_extract_location("online")).to eq("ONLINE")
      expect(helper.call_extract_location("TBA")).to eq("TBA")
      expect(helper.call_extract_location("Virtual")).to eq("VIRTUAL")
    end

    it "ignores term labels" do
      expect(helper.call_extract_location("FALL 2025")).to be_nil
      expect(helper.call_extract_location("COMP 1050")).to be_nil
    end

    it "returns nil for unrelated text" do
      expect(helper.call_extract_location("nothing useful")).to be_nil
    end

    it "keeps a single part of a room list as is" do
      expect(helper.call_expand_room_list("ZQXB", "101")).to eq("ZQXB 101")
    end

    it "keeps a letter part with no base number as is" do
      expect(helper.call_expand_room_list("ZQXB", "B/101")).to eq("ZQXB B / ZQXB 101")
    end
  end

  describe "#no_exam_entry?" do
    it "flags non-exam markers" do
      %w[ONLINE TBA VIRTUAL].each { |m| expect(helper.call_no_exam_entry?(m)).to be(true) }
      expect(helper.call_no_exam_entry?("see faculty")).to be(true)
    end

    it "does not flag a date" do
      expect(helper.call_no_exam_entry?("Monday, May 4, 2026")).to be(false)
    end
  end
end
