# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::IcsFeed do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.find_zone!("America/New_York") }
  let(:user) { create(:user, first_name: "Sample", last_name: "Student") }
  let(:term) { create(:term, start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 12, 20)) }
  let(:course) { create(:course, term: term, title: "data structures ii", subject: "COMP", course_number: 2000, section_number: "01") }
  let!(:meeting_time) { create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 1300, end_time: 1445) }

  around { |example| travel_to(zone.local(2026, 8, 20, 12)) { example.run } }

  before do
    allow(CourseCalendars::SyncJob).to receive(:perform_later)
    create(:enrollment, user: user, course: course)
  end

  def parsed(for_user = user)
    Icalendar::Calendar.parse(described_class.new(for_user).to_ical).first
  end

  def class_event(for_user = user)
    parsed(for_user).events.find { |e| e.uid.to_s.start_with?("course-") }
  end

  describe "an empty calendar" do
    it "has the calendar name and time zone, and no events, for a user with no courses" do
      calendar = parsed(create(:user, first_name: "Empty", last_name: "Student"))

      expect(calendar.events).to be_empty
      expect(calendar.custom_property("x_wr_calname")).to eq([ "WIT Course Schedule" ])
      expect(calendar.custom_property("x_wr_caldesc")).to eq([ "WIT Course Schedule Calendar for Empty Student" ])
      expect(calendar.timezones.map(&:tzid)).to eq([ "America/New_York" ])
    end

    it "asks calendar apps to fetch the feed again every hour" do
      body = described_class.new(user).to_ical

      expect(body).to include("REFRESH-INTERVAL;VALUE=DURATION:PT1H")
      expect(body).to include("X-PUBLISHED-TTL:PT1H")
    end
  end

  describe "a class event" do
    it "starts on the first class day and repeats weekly" do
      event = class_event

      expect(event.uid).to eq("course-#{course.crn}-meeting-#{meeting_time.id}@calendar-util.wit.edu")
      expect(event.dtstart).to eq(zone.local(2026, 9, 14, 13))
      expect(event.dtend).to eq(zone.local(2026, 9, 14, 14, 45))
      expect(event.rrule.first).to have_attributes(frequency: "WEEKLY", by_day: [ "MO" ])
    end

    it "is an all-day event with date values when the meeting time covers the whole day" do
      meeting_time.update!(begin_time: 1201, end_time: 2359)

      event = class_event

      expect(event.dtstart).to eq(Date.new(2026, 9, 14))
      expect(event.dtend).to eq(Date.new(2026, 9, 15))
      expect(event.rrule.first.until).to eq("20261215")
    end

    it "makes one event from meeting times with the same day and hours, and keeps the one with a real room" do
      tbd_building = create(:building, name: "TBD Hall")
      create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: tbd_building))
      real = create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 1300, end_time: 1445)
      hall = create(:building, name: "FCT Sample Hall")
      create(:course_meeting_time_room, meeting_time: real, room: create(:room, building: hall, number: "112"))

      events = parsed.events

      expect(events.map { |e| e.uid.to_s }).to eq([ "course-#{course.crn}-meeting-#{real.id}@calendar-util.wit.edu" ])
      expect(events.first.location).to eq("FCT Sample Hall - 112")
    end

    it "shows only the room number when the building is TBD" do
      tbd_building = create(:building, name: "TBD Hall")
      create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: tbd_building, number: "112"))

      expect(class_event.location).to eq("112")
    end

    it "has no location when the class has no room" do
      expect(class_event.location).to be_nil
    end
  end

  describe "preferences and templates" do
    it "uses the default title template and the default lecture color when the user set no preference" do
      expect(class_event.summary).to eq("data structures ii")
      expect(class_event.color).to eq(user.user_extension_config.default_color_lecture)
    end

    it "renders the title and description templates of the meeting time" do
      create(:event_preference, user: user, preferenceable: meeting_time, title_template: "{{course_code}} {{title}}",
                                description_template: "On {{day}}", color_id: "#1a2b3c")

      event = class_event

      expect(event.summary).to eq("COMP-2000-01 data structures ii")
      expect(event.description).to eq("On Monday")
      expect(event.color).to eq("#1a2b3c")
      expect(event.custom_property("x_apple_calendar_color")).to eq([ "#1a2b3c" ])
    end

    it "renders a global description template for every class" do
      create(:calendar_preference, user: user, scope: :global, description_template: "Section {{section_number}}")

      expect(class_event.description).to eq("Section 01")
    end
  end

  describe "holiday EXDATEs" do
    def holiday(category: "holiday", from:, to:)
      create(:university_calendar_event, category: category, summary: "Day Off", start_time: from, end_time: to)
    end

    it "skips the class on a one-day holiday on the class weekday" do
      holiday(from: zone.local(2026, 10, 12), to: zone.local(2026, 10, 12, 23, 59))

      expect(class_event.exdate.flatten).to eq([ zone.local(2026, 10, 12, 13) ])
    end

    it "skips each class weekday of a holiday of more than one day, and no other day" do
      holiday(from: zone.local(2026, 11, 20), to: zone.local(2026, 12, 1, 23, 59))
      holiday(category: "study_day", from: zone.local(2026, 10, 14), to: zone.local(2026, 10, 14, 23, 59))

      expect(class_event.exdate.flatten).to eq([ zone.local(2026, 11, 23, 13), zone.local(2026, 11, 30, 13) ])
    end

    it "uses date values for an all-day class" do
      meeting_time.update!(begin_time: 1201, end_time: 2359)
      holiday(from: zone.local(2026, 10, 12), to: zone.local(2026, 10, 12, 23, 59))

      expect(class_event.exdate.flatten).to eq([ Date.new(2026, 10, 12) ])
    end
  end

  describe "the end of the weekly rule" do
    def until_date
      class_event.rrule.first.until.then { |u| Time.zone.parse(u).in_time_zone(zone).to_date }
    end

    it "ends on the last day of the meeting time when the term has no finals" do
      expect(until_date).to eq(Date.new(2026, 12, 15))
    end

    it "ends the day before the course's own final" do
      create(:final_exam, term: term, crn: course.crn, course: course, exam_date: Date.new(2026, 12, 10))

      expect(until_date).to eq(Date.new(2026, 12, 9))
    end

    it "ends the day before the first final of the term when the course has none" do
      create(:final_exam, term: term, exam_date: Date.new(2026, 12, 8))

      expect(until_date).to eq(Date.new(2026, 12, 7))
    end

    it "ends before the finals period of the term when it comes first" do
      create(:final_exam, term: term, crn: course.crn, course: course, exam_date: Date.new(2026, 12, 14))
      create(:university_calendar_event, term: term, category: "finals", summary: "Final Exam Period",
                                         start_time: zone.local(2026, 12, 11), end_time: zone.local(2026, 12, 18))

      expect(until_date).to eq(Date.new(2026, 12, 10))
    end
  end

  describe "finals" do
    it "adds an event for each upcoming final of the user's courses" do
      final = create(:final_exam, term: term, crn: course.crn, course: course, exam_date: Date.new(2026, 12, 10),
                                  start_time: 800, end_time: 1000, location: "Room 112")

      event = parsed.events.find { |e| e.uid == "final-exam-#{final.id}@calendar-util.wit.edu" }

      expect(event.summary).to eq("Final Exam: Data Structures II")
      expect(event.description).to eq("COMP-2000-01")
      expect(event.location).to eq("Room 112")
      expect(event.dtstart).to eq(zone.local(2026, 12, 10, 8))
      expect(event.dtend).to eq(zone.local(2026, 12, 10, 10))
    end

    it "leaves out a final that is in the past" do
      create(:final_exam, term: term, crn: course.crn, course: course, exam_date: Date.new(2026, 8, 1))

      expect(parsed.events.map { |e| e.uid.to_s }).not_to include(a_string_starting_with("final-exam-"))
    end
  end

  describe "university events" do
    it "adds every holiday in the term dates as a free all-day event" do
      create(:university_calendar_event, ics_uid: "holiday-1", category: "holiday", summary: "Columbus Day",
                                         start_time: zone.local(2026, 10, 12), end_time: zone.local(2026, 10, 12, 23, 59))

      event = parsed.events.find { |e| e.uid == "university-holiday-1@calendar-util.wit.edu" }

      expect(event.summary).to eq("🏫 Columbus Day - No Classes")
      expect(event.dtstart).to eq(Date.new(2026, 10, 12))
      expect(event.transp).to eq("TRANSPARENT")
    end

    it "uses the meeting time dates when no term has start and end dates" do
      term.update!(start_date: nil, end_date: nil)
      create(:university_calendar_event, ics_uid: "holiday-2", category: "holiday", summary: "Columbus Day",
                                         start_time: zone.local(2026, 10, 12), end_time: zone.local(2026, 10, 12, 23, 59))

      expect(parsed.events.map { |e| e.uid.to_s }).to include("university-holiday-2@calendar-util.wit.edu")
    end

    it "adds the synced categories only when the user turned the sync on" do
      create(:university_calendar_event, ics_uid: "reg-1", category: "registration", summary: "Registration Opens",
                                         start_time: zone.local(2026, 10, 1, 9), end_time: zone.local(2026, 10, 1, 10))
      uids = -> { parsed.events.map { |e| e.uid.to_s } }

      expect(uids.call).not_to include("university-reg-1@calendar-util.wit.edu")

      user.user_extension_config.update!(sync_university_events: true, university_event_categories: %w[registration])

      expect(uids.call).to include("university-reg-1@calendar-util.wit.edu")
    end
  end

  it "gives the same bytes for the same data at a later time" do
    first = described_class.new(user).to_ical

    travel 5.minutes

    expect(described_class.new(user).to_ical).to eq(first)
  end
end
