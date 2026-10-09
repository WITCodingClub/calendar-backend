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

  describe "#location_for" do
    it "shows TBD for a placeholder room" do
      expect(builder.location_for(meeting_time_with_room("0"))).to eq("TBD")
    end

    it "shows only the room when the building is a placeholder" do
      tbd_building = create(:building, name: "To Be Determined")

      expect(builder.location_for(meeting_time_with_room("204", room_building: tbd_building))).to eq("204")
    end

    it "returns nil for a meeting time with no room" do
      expect(builder.location_for(create(:course_meeting_time, course: course))).to be_nil
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

  describe "#tbd_building?" do
    it "is true for a placeholder name" do
      expect(builder.tbd_building?(build(:building, name: "TBD Hall"))).to be(true)
    end

    it "is false for a real building or no building" do
      expect(builder.tbd_building?(build(:building))).to be(false)
      expect(builder.tbd_building?(nil)).to be(false)
    end
  end

  describe "#tbd_location?" do
    it "is true when the room is a placeholder" do
      expect(builder.tbd_location?(build(:building), build(:room, number: "0"))).to be(true)
    end

    it "is false for a real room in a real building" do
      expect(builder.tbd_location?(build(:building), build(:room, number: "101"))).to be(false)
    end
  end
end
