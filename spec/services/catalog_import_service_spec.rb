# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImportService, type: :service do
  let(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

  describe "#call" do
    context "credit hours" do
      it "sets lab courses to 0 credit hours" do
        catalog_courses = [
          {
            "courseReferenceNumber"   => 12345,
            "term"                    => term.uid,
            "courseTitle"             => "Computer Science I - Lab",
            "subject"                 => "CS",
            "courseNumber"            => 101,
            "scheduleTypeDescription" => "Laboratory (LAB)",
            "sequenceNumber"          => "01",
            "creditHours"             => 4, # LeopardWeb incorrectly returns total course credits
            "meetingsFaculty"         => [
              {
                "meetingTime" => {
                  "startDate" => Time.zone.today.to_s,
                  "endDate"   => (Time.zone.today + 90.days).to_s
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
            "courseReferenceNumber"   => 12346,
            "term"                    => term.uid,
            "courseTitle"             => "Computer Science I",
            "subject"                 => "CS",
            "courseNumber"            => 101,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 4,
            "meetingsFaculty"         => [
              {
                "meetingTime" => {
                  "startDate" => Time.zone.today.to_s,
                  "endDate"   => (Time.zone.today + 90.days).to_s
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
            "courseReferenceNumber"   => 12347,
            "term"                    => term.uid,
            "courseTitle"             => "Test Course",
            "subject"                 => "TEST",
            "courseNumber"            => 101,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 3,
            "meetingsFaculty"         => [
              {
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025"
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        expect(result[:failed]).to eq(0)

        course = Course.find_by(crn: 12347)
        expect(course.start_date).to eq(Date.new(2025, 8, 15))
        expect(course.end_date).to eq(Date.new(2025, 12, 20))
      end

      it "handles missing dates gracefully" do
        catalog_courses = [
          {
            "courseReferenceNumber"   => 12348,
            "term"                    => term.uid,
            "courseTitle"             => "Test Course",
            "subject"                 => "TEST",
            "courseNumber"            => 102,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 3,
            "meetingsFaculty"         => [
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
            "courseReferenceNumber"   => 12349,
            "term"                    => term.uid,
            "courseTitle"             => "Test Course",
            "subject"                 => "TEST",
            "courseNumber"            => 103,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 3,
            "meetingsFaculty"         => [
              {
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025"
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

    # rubocop:disable RSpec/ExampleLength
    context "meeting time deduplication" do
      it "deduplicates meeting times with same schedule, preferring those with location" do
        catalog_courses = [
          {
            "courseReferenceNumber"   => 12350,
            "term"                    => term.uid,
            "courseTitle"             => "Duplicate Meeting Test",
            "subject"                 => "TEST",
            "courseNumber"            => 104,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 3,
            "meetingsFaculty"         => [
              {
                # Entry without location
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025",
                  "beginTime" => "0930",
                  "endTime"   => "1040",
                  "monday"    => true,
                  "wednesday" => true,
                  "friday"    => true,
                  "building"  => nil,
                  "room"      => nil
                }
              },
              {
                # Entry with location (same schedule)
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025",
                  "beginTime" => "0930",
                  "endTime"   => "1040",
                  "monday"    => true,
                  "wednesday" => true,
                  "friday"    => true,
                  "building"  => "WILLS",
                  "room"      => "102"
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        expect(result[:failed]).to eq(0)

        course = Course.find_by(crn: 12350)
        # Should only create 3 meeting times (M/W/F), not 6
        expect(course.meeting_times.count).to eq(3)

        # All should have the valid building
        course.meeting_times.each do |mt|
          expect(mt.building.abbreviation).to eq("WILLS")
          expect(mt.room.number).to eq("102")
        end
      end

      it "keeps meeting time without location when no location variant exists" do
        catalog_courses = [
          {
            "courseReferenceNumber"   => 12351,
            "term"                    => term.uid,
            "courseTitle"             => "TBD Location Test",
            "subject"                 => "TEST",
            "courseNumber"            => 105,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 3,
            "meetingsFaculty"         => [
              {
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025",
                  "beginTime" => "1100",
                  "endTime"   => "1215",
                  "monday"    => true,
                  "wednesday" => true,
                  "building"  => nil,
                  "room"      => nil
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        course = Course.find_by(crn: 12351)
        expect(course.meeting_times.count).to eq(2) # M/W
      end

      it "handles multiple different time slots correctly" do
        catalog_courses = [
          {
            "courseReferenceNumber"   => 12352,
            "term"                    => term.uid,
            "courseTitle"             => "Multiple Slots Test",
            "subject"                 => "TEST",
            "courseNumber"            => 106,
            "scheduleTypeDescription" => "Lecture (LEC)",
            "sequenceNumber"          => "01",
            "creditHours"             => 3,
            "meetingsFaculty"         => [
              {
                # Morning slot without location
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025",
                  "beginTime" => "0800",
                  "endTime"   => "0850",
                  "monday"    => true,
                  "building"  => nil,
                  "room"      => nil
                }
              },
              {
                # Morning slot with location
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025",
                  "beginTime" => "0800",
                  "endTime"   => "0850",
                  "monday"    => true,
                  "building"  => "DOBBS",
                  "room"      => "203"
                }
              },
              {
                # Afternoon slot (different time, only one entry)
                "meetingTime" => {
                  "startDate" => "08/15/2025",
                  "endDate"   => "12/20/2025",
                  "beginTime" => "1400",
                  "endTime"   => "1450",
                  "wednesday" => true,
                  "building"  => "WENTW",
                  "room"      => "312"
                }
              }
            ]
          }
        ]

        result = described_class.new(catalog_courses).call

        expect(result[:processed]).to eq(1)
        course = Course.find_by(crn: 12352)
        # Should have 2 meeting times: Monday morning + Wednesday afternoon
        expect(course.meeting_times.count).to eq(2)

        monday_mt = course.meeting_times.find_by(day_of_week: :monday)
        expect(monday_mt.building.abbreviation).to eq("DOBBS")

        wednesday_mt = course.meeting_times.find_by(day_of_week: :wednesday)
        expect(wednesday_mt.building.abbreviation).to eq("WENTW")
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
