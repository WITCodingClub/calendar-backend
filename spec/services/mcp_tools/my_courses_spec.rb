# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyCourses do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "lists the user's courses in the term without calendar settings" do
    course = create(:course, term: term, title: "Data Structures")
    create(:course_meeting_time, course: course)
    create(:enrollment, user: user, course: course)
    create(:enrollment, course: create(:course, term: term))

    result = call(term_uid: term.uid)

    courses = result.structured_content[:courses]
    expect(courses.pluck(:title)).to eq([ "Data Structures" ])
    expect(courses.first[:meeting_times].first).to include(begin_time: "09:00", monday: true)
    expect(courses.first[:meeting_times].first).not_to have_key(:calendar_config)
  end
end
