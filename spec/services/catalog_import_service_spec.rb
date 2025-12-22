# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImportService, type: :service do
  let(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

  describe "#call" do
    context "credit hours" do
      it "sets lab courses to 0 credit hours" do
        catalog_courses = [
          {
            "courseReferenceNumber" => 12345,
            "term" => term.uid,
            "courseTitle" => "Computer Science I - Lab",
            "subject" => "CS",
            "courseNumber" => 101,
            "scheduleTypeDescription" => "Laboratory (LAB)",
            "sequenceNumber" => "01",
            "creditHours" => 4, # LeopardWeb incorrectly returns total course credits
            "meetingsFaculty" => [
              {
                "meetingTime" => {
                  "startDate" => Time.zone.today.to_s,
                  "endDate" => (Time.zone.today + 90.days).to_s
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        expect(result[:failed]).to eq(0)

        course = Course.find_by(crn: 12345)
        expect(course.credit_hours).to eq(0)
        expect(course.schedule_type).to eq("laboratory")
      end

      it "keeps lecture courses with original credit hours" do
        catalog_courses = [
          {
            "courseReferenceNumber" => 12346,
            "term" => term.uid,
            "courseTitle" => "Computer Science I",
            "subject" => "CS",
            "courseNumber" => 101,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber" => "01",
            "creditHours" => 4,
            "meetingsFaculty" => [
              {
                "meetingTime" => {
                  "startDate" => Time.zone.today.to_s,
                  "endDate" => (Time.zone.today + 90.days).to_s
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        expect(result[:failed]).to eq(0)

        course = Course.find_by(crn: 12346)
        expect(course.credit_hours).to eq(4)
        expect(course.schedule_type).to eq("lecture")
      end
    end

    context "date parsing" do
      it "parses MM/DD/YYYY format dates correctly" do
        catalog_courses = [
          {
            "courseReferenceNumber" => 12347,
            "term" => term.uid,
            "courseTitle" => "Test Course",
            "subject" => "TEST",
            "courseNumber" => 101,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber" => "01",
            "creditHours" => 3,
            "meetingsFaculty" => [
              {
                "meetingTime" => {
                  "startDate" => "01/06/2026",
                  "endDate" => "04/14/2026"
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        expect(result[:failed]).to eq(0)

        course = Course.find_by(crn: 12347)
        expect(course.start_date).to eq(Date.new(2026, 1, 6))
        expect(course.end_date).to eq(Date.new(2026, 4, 14))
      end

      it "handles missing dates gracefully" do
        catalog_courses = [
          {
            "courseReferenceNumber" => 12348,
            "term" => term.uid,
            "courseTitle" => "Test Course",
            "subject" => "TEST",
            "courseNumber" => 102,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber" => "01",
            "creditHours" => 3,
            "meetingsFaculty" => [
              {
                "meetingTime" => {}
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        expect(result[:failed]).to eq(0)

        course = Course.find_by(crn: 12348)
        expect(course.start_date).to be_nil
        expect(course.end_date).to be_nil
      end

      it "updates term dates after importing courses" do
        catalog_courses = [
          {
            "courseReferenceNumber" => 12349,
            "term" => term.uid,
            "courseTitle" => "Test Course",
            "subject" => "TEST",
            "courseNumber" => 103,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber" => "01",
            "creditHours" => 3,
            "meetingsFaculty" => [
              {
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate" => "12/20/2025"
                }
              }
            ]
          }
        ]

        described_class.new(catalog_courses).call

        term.reload
        expect(term.start_date).to eq(Date.new(2025, 8, 15))
        expect(term.end_date).to eq(Date.new(2025, 12, 20))
      end
    end
  end
end
