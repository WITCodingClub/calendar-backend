# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CourseProcessorService, type: :service do
  let(:user) { create(:user) }
  let(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

  describe '#call' do
    context 'validation' do
      it 'raises error when courses is nil' do
        expect {
          described_class.new(nil, user).call
        }.to raise_error(ArgumentError, /courses cannot be nil/)
      end

      it 'raises error when courses is not an array' do
        expect {
          described_class.new("not an array", user).call
        }.to raise_error(ArgumentError, /courses must be an array/)
      end

      it 'raises error when courses is empty' do
        expect {
          described_class.new([], user).call
        }.to raise_error(ArgumentError, /courses cannot be empty/)
      end

      it 'raises error when course is not a hash' do
        courses = ["not a hash"]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /must be a hash/)
      end

      it 'raises error when crn is missing' do
        courses = [{ term: 202610 }]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /missing required field: crn/)
      end

      it 'raises error when term is missing' do
        courses = [{ crn: 12345 }]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /missing required field: term/)
      end

      it 'raises error when term UID is not numeric' do
        courses = [{ crn: 12345, term: "invalid" }]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /invalid term UID/)
      end
    end

    context 'term lookup' do
      it 'raises InvalidTermError when term does not exist' do
        courses = [{ crn: 12345, term: 999999 }]

        expect {
          described_class.new(courses, user).call
        }.to raise_error(InvalidTermError) do |error|
          expect(error.uid).to eq(999999)
          expect(error.message).to include("Term with UID 999999 not found")
        end
      end

      it 'successfully finds term when it exists' do
        courses = [{
          crn: 12345,
          term: term.uid,
          start: Date.today,
          end: Date.today + 90.days,
          courseNumber: "CS101"
        }]

        # Mock LeopardWebService responses
        allow(LeopardWebService).to receive(:get_class_details).and_return({
          associated_term: "Fall 2025",
          subject: "CS",
          title: "Intro to CS",
          schedule_type: "Lecture (LEC)",
          section_number: "01",
          credit_hours: 3,
          grade_mode: "Normal"
        })

        allow(LeopardWebService).to receive(:get_faculty_meeting_times).and_return({
          "fmt" => []
        })

        expect {
          described_class.new(courses, user).call
        }.not_to raise_error
      end
    end

    context 'deduplication' do
      before do
        allow(LeopardWebService).to receive(:get_class_details).and_return({
          associated_term: "Fall 2025",
          subject: "CS",
          title: "Intro to CS",
          schedule_type: "Lecture (LEC)",
          section_number: "01",
          credit_hours: 3,
          grade_mode: "Normal"
        })

        allow(LeopardWebService).to receive(:get_faculty_meeting_times).and_return({
          "fmt" => []
        })
      end

      it 'deduplicates courses by CRN and term' do
        courses = [
          { crn: 12345, term: term.uid, start: Date.today, end: Date.today + 90.days, courseNumber: "CS101" },
          { crn: 12345, term: term.uid, start: Date.today, end: Date.today + 90.days, courseNumber: "CS101" },
          { crn: 12345, term: term.uid, start: Date.today, end: Date.today + 90.days, courseNumber: "CS101" }
        ]

        # Should only call LeopardWebService once
        expect(LeopardWebService).to receive(:get_class_details).once
        expect(LeopardWebService).to receive(:get_faculty_meeting_times).once

        result = described_class.new(courses, user).call
        expect(result.length).to eq(1)
      end
    end
  end
end
