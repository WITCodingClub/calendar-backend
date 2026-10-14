# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyFinals do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  it "lists the finals of the user's courses in the term" do
    course = create(:course, term: term, subject: "COMP", course_number: 2000, title: "Algorithms")
    create(:enrollment, user: user, course: course)
    create(:final_exam, term: term, crn: course.crn, course: course, location: "WENTW 010")

    result = described_class.call(server_context: { user: user }, term_uid: term.uid)

    expect(result.structured_content[:finals]).to eq([ {
      course:     "#{course.prefix}2000 Algorithms".squish,
      crn:        course.crn,
      date:       "2026-12-17",
      start_time: "08:00",
      end_time:   "10:00",
      location:   "WENTW 010"
    } ])
  end
end
