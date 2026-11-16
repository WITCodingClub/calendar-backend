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

  [
    "Spring 2027 Final Exam Schedule Available to Students",
    "Summer 2027 Final Exam Schedule Available to Students",
    "Summer 2026 Final Exam Schedule Availabl",
    "Final exam schedule posted"
  ].each do |summary|
    it "puts the finals schedule announcement #{summary.inspect} in academic, not finals" do
      expect(described_class.infer(summary, nil)).to eq("academic")
    end
  end

  [ "Final Exam Period (15-week & 2nd 7-week classes)", "Final Exams (15-week & 2 nd 7-week classes)" ].each do |summary|
    it "keeps the exam period #{summary.inspect} in finals" do
      expect(described_class.infer(summary, "Calendar Announcement")).to eq("finals")
    end
  end

  {
    "Final Exam Schedules Available" => "academic",
    "Spring 2027 Final Exam Schedule Now Available" => "academic",
    "Final Exam Schedule - Available" => "academic",
    "Final Exam Schedule Is Live" => "academic",
    "Final Exam Schedule Av" => "academic",
    "Final Exam Schedule" => "academic",
    "Final Exam Conflict Requests Due" => "deadline",
    "Submit Final Exam Conflict Form by Friday" => "deadline",
    "Final Exams (see schedule posted)" => "finals",
    "Final Exam Period - Grade Submission Opens" => "finals",
    "Final Examinations" => "finals",
    "Exam Period" => "finals"
  }.each do |summary, category|
    it "puts the finals-word title #{summary.inspect} in #{category}" do
      expect(described_class.infer(summary, nil)).to eq(category)
    end
  end

  it "puts a deadline that names final exams in deadline, not finals" do
    expect(described_class.infer("Deadline to Submit Final Exam Conflict Requests", "Calendar Announcement")).to eq("deadline")
  end

  it "keeps \"Finals Week\" in finals" do
    expect(described_class.infer("Finals Week", nil)).to eq("finals")
  end

  it "leaves a schedule announcement that is not about finals to the other rules" do
    expect(described_class.infer("Fall 2027 Course Schedule Available to Students", "Calendar Announcement")).to eq("academic")
    expect(described_class.infer("Fall 2027 Course Schedule Available to Students", nil)).to eq("campus_event")
  end

  it "handles nil input" do
    expect(described_class.infer(nil, nil)).to eq("campus_event")
  end

  it "reads a holiday word before any other category" do
    expect(described_class.infer("Thanksgiving Recess Registration", nil)).to eq("holiday")
  end
end
