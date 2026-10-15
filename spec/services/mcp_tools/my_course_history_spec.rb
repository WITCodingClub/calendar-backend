# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyCourseHistory do
  let(:user) { create(:user) }

  it "lists each term the user processed, newest first, with its courses" do
    older = create(:term, year: 2025, season: :fall)
    newer = create(:term, year: 2026, season: :spring)
    create(:term, year: 2026, season: :fall)
    old_course = create(:course, term: older, title: "Data Structures")
    create(:course_meeting_time, course: old_course)
    create(:enrollment, user: user, course: old_course)
    create(:enrollment, user: user, course: create(:course, term: newer, title: "Algorithms"))
    create(:enrollment, course: create(:course, term: older))

    result = described_class.call(server_context: mcp_context(user))

    terms = result.structured_content[:terms]
    expect(terms.pluck(:uid)).to eq([ newer.uid, older.uid ])
    expect(terms.pluck(:name)).to eq([ "Spring 2026", "Fall 2025" ])
    expect(terms.map { |term| term[:courses].pluck(:title) }).to eq([ [ "Algorithms" ], [ "Data Structures" ] ])

    course = terms.last[:courses].first
    expect(course).not_to have_key(:term)
    expect(course[:meeting_times].first).to include(begin_time: "09:00", monday: true)
    expect(course[:meeting_times].first).not_to have_key(:calendar_config)
  end

  it "lists no terms for a user with no courses" do
    expect(described_class.call(server_context: mcp_context(user)).structured_content).to eq(terms: [])
  end
end
