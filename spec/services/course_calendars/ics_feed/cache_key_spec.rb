# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::IcsFeed::CacheKey do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)         { Time.find_zone!("America/New_York") }
  let(:user)         { create(:user) }
  let(:term)         { create(:term) }
  let(:course)       { create(:course, term: term) }
  let(:faculty)      { create(:faculty) }
  let(:building)     { create(:building) }
  let(:room)         { create(:room, building: building) }
  let(:meeting_time) { create(:course_meeting_time, course: course, day_of_week: :monday) }
  let!(:course_faculty) { create(:course_faculty, course: course, faculty: faculty) }

  # A time after the real clock: rows that other specs leave in the table
  # (fixtures) have the real time, and they would hide a newer updated_at.
  around { |example| travel_to(zone.local(2030, 10, 7, 12)) { example.run } }

  before do
    create(:course_meeting_time_room, meeting_time: meeting_time, room: room)
    create(:enrollment, user: user, course: course, term: term)
  end

  def key
    described_class.new(user.reload).to_s
  end

  # Runs the change one minute later, so every new updated_at differs.
  def expect_new_key
    before = key
    travel(1.minute)
    yield
    expect(key).not_to eq(before)
  end

  it "gives the same key when nothing changed" do
    expect(key).to eq(key)
  end

  it "reads every fingerprint in one query" do
    # The no-class days come from their own cache entry, not this query.
    allow(UniversityCalendarEvent).to receive(:cached_no_class_spans).and_return([])
    user.reload
    queries = count_queries { described_class.new(user).to_s }

    expect(queries).to eq(1)
  end

  it "does not change when another user's course changes" do
    other_course = create(:course, term: term)
    create(:enrollment, user: create(:user), course: other_course, term: term)
    before = key
    travel(1.minute)

    other_course.update!(title: "Synthetic Other Title")

    expect(key).to eq(before)
  end

  it "changes when a course changes" do
    expect_new_key { course.update!(title: "Synthetic New Title") }
  end

  it "changes when the user enrolls in another course" do
    expect_new_key { create(:enrollment, user: user, course: create(:course, term: term), term: term) }
  end

  it "changes when a meeting time is deleted" do
    other = create(:course_meeting_time, course: course, day_of_week: :wednesday)
    expect_new_key { other.destroy! }
  end

  it "changes when a room or its building changes" do
    expect_new_key { room.update!(number: "999") }
    expect_new_key { building.update!(name: "Synthetic Renamed Hall") }
  end

  it "changes when a faculty member changes" do
    expect_new_key { faculty.update!(email: "synthetic.renamed@wit.edu") }
  end

  it "changes when the primary faculty changes, though courses_faculties has no timestamps" do
    expect_new_key { course_faculty.update!(primary_indicator: !course_faculty.primary_indicator) }
  end

  it "changes when another course in the term gets a final" do
    expect_new_key { create(:final_exam, term: term, course: create(:course, term: term)) }
  end

  it "changes when a university event is added" do
    expect_new_key { create(:university_calendar_event) }
  end

  it "changes when a university event is deleted" do
    event = create(:university_calendar_event)
    expect_new_key { event.destroy! }
  end

  it "changes when the building of a final's location changes, though no class meets there" do
    other_building = create(:building)
    create(:final_exam, term: term, course: course, location: "#{other_building.abbreviation} 201")
    expect_new_key { other_building.update!(name: "Synthetic Exam Hall") }
  end

  it "changes when the faculty member of a course is replaced" do
    expect_new_key { course_faculty.update!(faculty: create(:faculty)) }
  end

  it "changes when the user turns on university events" do
    config = user.user_extension_config
    expect_new_key { config.update!(sync_university_events: !config.sync_university_events) }
  end

  it "changes when the cached no-class days change" do
    allow(UniversityCalendarEvent).to receive(:cached_no_class_spans).and_return([])
    before = key

    allow(UniversityCalendarEvent).to receive(:cached_no_class_spans)
      .and_return([ [ zone.local(2030, 11, 11), zone.local(2030, 11, 11, 23, 59), Time.current ] ])

    expect(key).not_to eq(before)
  end

  it "changes when the user saves a preference" do
    expect_new_key { create(:event_preference, user: user, preferenceable: meeting_time) }
  end

  it "changes when the user's name changes" do
    expect_new_key { user.update!(first_name: "Synthetic") }
  end

  it "changes on the next day" do
    before = key
    travel(1.day)

    expect(key).not_to eq(before)
  end

  it "changes when a friend meeting in the feed ends" do
    create(:friend_meeting, user: user, destinations: %w[ics],
                            start_time: zone.local(2030, 10, 7, 13), end_time: zone.local(2030, 10, 7, 14))
    before = key
    travel_to(zone.local(2030, 10, 7, 15))

    expect(key).not_to eq(before)
  end
end
