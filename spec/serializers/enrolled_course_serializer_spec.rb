# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnrolledCourseSerializer do
  let(:user)     { create(:user) }
  let(:course)   { create(:course) }
  let(:building) { create(:building, abbreviation: "FES") }

  def serialize
    enrollment = create(:enrollment, user: user, course: course)
    described_class.new(enrollment.reload, term: course.term,
                                           preference_resolver: Preferences::Resolver.new(user),
                                           template_renderer: Preferences::TemplateRenderer.new,
                                           recurrence: CourseCalendars::RecurrenceBuilder.new(user)).as_json
  end

  def meeting_time_in(*numbers)
    create(:course_meeting_time, course: course, day_of_week: :monday).tap do |meeting_time|
      numbers.each { |n| create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: building, number: n)) }
    end
  end

  it "keeps the meeting time with a room over one with no room" do
    meeting_time_in
    real = meeting_time_in("101")

    expect(serialize[:meeting_times].pluck(:id)).to eq([ real.public_id ])
  end

  it "keeps the first row when it has a real room next to room 0" do
    mixed = meeting_time_in("0", "101")
    meeting_time_in("102")

    expect(serialize[:meeting_times].pluck(:id, :building_room)).to eq([ [ mixed.public_id, "FES 101" ] ])
  end
end
