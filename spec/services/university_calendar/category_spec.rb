# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::Category do
  {
    "Thanksgiving Recess" => "holiday",
    "Spring Break" => "holiday",
    "Labor Day" => "holiday",
    "Martin Luther King Jr. Day" => "holiday",
    "No Classes" => "holiday",
    "Juneteenth" => "holiday",
    "Classes Begin" => "term_dates",
    "Last Day of Classes" => "term_dates",
    "Study Day" => "study_day",
    "Reading Period" => "study_day",
    "Final Exam Period" => "finals",
    "Finals Week" => "finals",
    "Commencement" => "graduation",
    "Registration Opens" => "registration",
    "Add/Drop Period" => "registration",
    "Last day to withdraw" => "deadline",
    "Tuition Due" => "deadline"
  }.each do |summary, category|
    it "puts #{summary.inspect} in #{category}" do
      expect(described_class.infer(summary, nil)).to eq(category)
    end
  end

  {
    "Calendar Announcement" => "academic",
    "Meeting" => "meeting",
    "Art Exhibit" => "exhibit",
    "Showcase" => "exhibit",
    "Announcement" => "announcement",
    "Something else" => "campus_event"
  }.each do |raw, category|
    it "falls back to #{category} for the raw type #{raw.inspect}" do
      expect(described_class.infer("Nothing special", raw)).to eq(category)
    end
  end

  it "handles nil input" do
    expect(described_class.infer(nil, nil)).to eq("campus_event")
  end

  it "reads a holiday word before any other category" do
    expect(described_class.infer("Thanksgiving Recess Registration", nil)).to eq("holiday")
  end
end
