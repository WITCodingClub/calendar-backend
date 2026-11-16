# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::EventBuilder do
  subject(:builder) { described_class.new(user) }

  let(:user)     { create(:user) }
  let(:term)     { create(:term) }
  let(:course)   { create(:course, term: term, subject: "COMP", course_number: 1050, section_number: "02", title: "Programming") }
  let(:building) { create(:building) }
  let(:config)   { user.user_extension_config }

  def meeting_time_with_room(number, room_building: building, **attributes)
    meeting_time = create(:course_meeting_time, course: course, **attributes)
    create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: room_building, number: number))
    meeting_time
  end

  def university_event(category:, start_time:, summary: "Factory University Event")
    create(:university_calendar_event, summary: summary, category: category, all_day: true,
                                       start_time: start_time, end_time: start_time + 1.day)
  end

  describe "#meeting_time_event" do
    it "builds the event of a meeting time" do
      meeting_time = meeting_time_with_room("101", day_of_week: :monday, begin_time: 900, end_time: 1015)

      expect(builder.meeting_time_event(meeting_time)).to include(
        summary: "Programming",
        description: "COMP-1050-02",
        course_code: "COMP-1050-02",
        location: "#{building.name} - 101",
        start_time: Time.zone.local(2026, 9, 14, 9, 0),
        end_time: Time.zone.local(2026, 9, 14, 10, 15),
        meeting_time_id: meeting_time.id,
        all_day: false
      )
      expect(builder.meeting_time_event(meeting_time)[:recurrence].first).to start_with("RRULE:FREQ=WEEKLY")
    end

    it "uses the injected recurrence builder" do
      recurrence = instance_double(CourseCalendars::RecurrenceBuilder, find_first_meeting_date: nil)
      meeting_time = create(:course_meeting_time, course: course)

      expect(described_class.new(user, recurrence: recurrence).meeting_time_event(meeting_time)).to be_nil
    end
  end

  describe "#course_events" do
    before do
      create(:enrollment, user: user, course: course)
      meeting_time_with_room("0", day_of_week: :monday)
      meeting_time_with_room("101", day_of_week: :monday)
    end

    it "keeps one meeting time with a real location when two share a day and times" do
      events = builder.course_events(user.enrollments, prefer_valid_locations: true)

      expect(events.pluck(:location)).to eq([ "#{building.name} - 101" ])
    end

    it "keeps the meeting time with a room over one with no room" do
      hall  = create(:building)
      other = create(:course, term: term)
      create(:enrollment, user: user, course: other)
      create(:course_meeting_time, course: other, day_of_week: :tuesday)
      create(:course_meeting_time_room, meeting_time: create(:course_meeting_time, course: other, day_of_week: :tuesday),
                                        room: create(:room, building: hall, number: "101"))

      events = builder.course_events(Enrollment.where(course: other), prefer_valid_locations: true)

      expect(events.pluck(:location)).to eq([ "#{hall.name} - 101" ])
    end

    it "keeps the first row when it has a real room next to room 0" do
      hall  = create(:building)
      other = create(:course, term: term)
      create(:enrollment, user: user, course: other)
      mixed = create(:course_meeting_time, course: other, day_of_week: :tuesday)
      %w[0 101].each { |n| create(:course_meeting_time_room, meeting_time: mixed, room: create(:room, building: hall, number: n)) }
      create(:course_meeting_time_room, meeting_time: create(:course_meeting_time, course: other, day_of_week: :tuesday),
                                        room: create(:room, building: hall, number: "102"))

      events = builder.course_events(Enrollment.where(course: other), prefer_valid_locations: true)

      # Room 0 next to 101 is not all TBD, so the first row stays.
      expect(events.pluck(:location)).to eq([ "#{hall.name} - 101" ])
    end

    it "keeps every meeting time when it does not filter" do
      events = builder.course_events(user.enrollments, prefer_valid_locations: false)

      expect(events.pluck(:location)).to contain_exactly("TBD", "#{building.name} - 101")
    end
  end

  describe "#finals_events" do
    let!(:future_final) { create(:final_exam, course: course, term: term, exam_date: 1.week.from_now.to_date) }
    let!(:past_final)   { create(:final_exam, course: course, term: term, exam_date: 1.week.ago.to_date) }

    before { create(:enrollment, user: user, course: course) }

    it "builds future finals by default" do
      expect(builder.finals_events).to contain_exactly(
        a_hash_including(final_exam_id: future_final.id, summary: "Final Exam: Programming", course_code: "COMP-1050-02", recurrence: nil)
      )
    end

    it "builds past finals for the backfill" do
      expect(builder.finals_events(time_scope: :past).pluck(:final_exam_id)).to eq([ past_final.id ])
    end

    it "builds every final without a time scope" do
      expect(builder.finals_events(time_scope: :all).pluck(:final_exam_id)).to contain_exactly(future_final.id, past_final.id)
    end

    it "returns no finals for a user with no enrollments" do
      expect(described_class.new(create(:user)).finals_events).to eq([])
    end
  end

  describe "#university_events" do
    let!(:holiday) { university_event(category: "holiday", summary: "Fall Break", start_time: 1.week.from_now) }

    it "always adds holidays as all-day events" do
      expect(builder.university_events).to contain_exactly(
        a_hash_including(university_calendar_event_id: holiday.id, summary: "🏫 Fall Break - No Classes", all_day: true)
      )
    end

    it "adds the selected categories when university event sync is on" do
      config.update!(sync_university_events: true, university_event_categories: %w[registration])
      registration = university_event(category: "registration", start_time: 1.week.from_now)

      expect(builder.university_events.pluck(:university_calendar_event_id)).to contain_exactly(holiday.id, registration.id)
    end

    it "leaves out a selected category that no longer syncs" do
      config.update!(sync_university_events: true, university_event_categories: %w[registration campus_event])
      registration = university_event(category: "registration", start_time: 1.week.from_now)
      university_event(category: "campus_event", start_time: 1.week.from_now)

      expect(builder.university_events.pluck(:university_calendar_event_id)).to contain_exactly(holiday.id, registration.id)
    end

    it "builds only past events for the backfill" do
      past = university_event(category: "holiday", start_time: 2.months.ago)

      expect(builder.university_events(time_scope: :past).pluck(:university_calendar_event_id)).to eq([ past.id ])
    end
  end

  describe "with preferences" do
    subject(:builder) { described_class.new(user, preferences: Preferences::Applier.new(user)) }

    it "applies the person's templates and color to each event, as the sync does" do
      create(:enrollment, user: user, course: course)
      meeting_time = meeting_time_with_room("101", day_of_week: :monday)
      create(:event_preference, user: user, preferenceable: meeting_time, title_template: "{{course_code}}", color_id: "#1a2b3c")

      entry = builder.class_entries([ course.reload ]).sole

      expect(entry.source).to eq(meeting_time)
      expect(entry.event).to include(summary: "COMP-1050-02", color_id: "#1a2b3c", location: "#{building.name} 101")
    end
  end

  describe "#university_event_entries with a date range" do
    it "gives the events that overlap the dates" do
      inside  = university_event(category: "holiday", start_time: Time.zone.local(2026, 10, 12))
      university_event(category: "holiday", start_time: Time.zone.local(2027, 3, 1))

      entries = builder.university_event_entries(time_scope: Date.new(2026, 9, 1)..Date.new(2026, 12, 20))

      expect(entries.map(&:source)).to eq([ inside ])
    end
  end
end
