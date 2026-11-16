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

  describe "#class_events" do
    it "builds the event of a meeting time with the person's preferences" do
      create(:enrollment, user: user, course: course)
      meeting_time = meeting_time_with_room("101", day_of_week: :monday, begin_time: 900, end_time: 1015)

      event = builder.class_events.sole

      expect(event).to have_attributes(
        source: meeting_time,
        summary: "Programming",
        location: "#{building.name} 101",
        start_time: Time.zone.local(2026, 9, 14, 9, 0),
        end_time: Time.zone.local(2026, 9, 14, 10, 15),
        all_day: false
      )
      expect(event.recurrence.rule).to start_with("FREQ=WEEKLY")
    end

    it "builds no event without a first meeting date" do
      create(:enrollment, user: user, course: course)
      create(:course_meeting_time, course: course)
      recurrence = instance_double(CourseCalendars::RecurrenceBuilder, preload_for!: nil, find_first_meeting_date: nil)

      expect(described_class.new(user, recurrence: recurrence).class_events).to eq([])
    end

    it "applies the person's templates and color" do
      create(:enrollment, user: user, course: course)
      meeting_time = meeting_time_with_room("101", day_of_week: :monday)
      create(:event_preference, user: user, preferenceable: meeting_time, title_template: "{{course_code}}", color_id: "#1a2b3c")

      expect(builder.class_events.sole).to have_attributes(summary: "COMP-1050-02", color_id: "#1a2b3c")
    end

    context "with two meeting times on the same day and times" do
      before do
        create(:enrollment, user: user, course: course)
        meeting_time_with_room("0", day_of_week: :monday)
        meeting_time_with_room("101", day_of_week: :monday)
      end

      it "keeps the one with a real location" do
        expect(builder.class_events.map(&:location)).to eq([ "#{building.name} 101" ])
      end
    end

    it "keeps the meeting time with a room over one with no room" do
      hall = create(:building)
      create(:enrollment, user: user, course: course)
      create(:course_meeting_time, course: course, day_of_week: :tuesday)
      create(:course_meeting_time_room, meeting_time: create(:course_meeting_time, course: course, day_of_week: :tuesday),
                                        room: create(:room, building: hall, number: "101"))

      expect(builder.class_events.map(&:location)).to eq([ "#{hall.name} 101" ])
    end

    it "keeps the first row when it has a real room next to room 0" do
      hall = create(:building)
      create(:enrollment, user: user, course: course)
      mixed = create(:course_meeting_time, course: course, day_of_week: :tuesday)
      %w[0 101].each { |n| create(:course_meeting_time_room, meeting_time: mixed, room: create(:room, building: hall, number: n)) }
      create(:course_meeting_time_room, meeting_time: create(:course_meeting_time, course: course, day_of_week: :tuesday),
                                        room: create(:room, building: hall, number: "102"))

      # Room 0 next to 101 is not all TBD, so the first row stays.
      expect(builder.class_events.map(&:location)).to eq([ "#{hall.name} 101" ])
    end
  end

  # Prosopite raises in Prosopite.scan when the same query runs once for each
  # event (#654). The templates read the course, faculty, term, and rooms.
  it "builds the class events of several courses without one query for each" do
    3.times do
      other = create(:course, term: term)
      create(:enrollment, user: user, course: other)
      create(:course_faculty, course: other, faculty: create(:faculty))
      create(:course_meeting_time_room, meeting_time: create(:course_meeting_time, course: other, day_of_week: :monday),
                                        room: create(:room, building: building))
    end

    expect { Prosopite.scan { builder.class_events } }.not_to raise_error
  end

  describe "#final_exam_events" do
    let!(:future_final) { create(:final_exam, course: course, term: term, exam_date: 1.week.from_now.to_date) }
    let!(:past_final)   { create(:final_exam, course: course, term: term, exam_date: 1.week.ago.to_date) }

    before { create(:enrollment, user: user, course: course) }

    it "builds future finals by default" do
      expect(builder.final_exam_events.sole).to have_attributes(source: future_final, summary: "Final Exam: Programming",
                                                                 recurrence: nil)
    end

    it "builds past finals for the backfill" do
      expect(builder.final_exam_events(time_scope: :past).map(&:source)).to eq([ past_final ])
    end

    it "returns no finals for a user with no enrollments" do
      expect(described_class.new(create(:user)).final_exam_events).to eq([])
    end
  end

  describe "#university_events" do
    let!(:holiday) { university_event(category: "holiday", summary: "Fall Break", start_time: 1.week.from_now) }

    # The default title template is {{summary}}, so the holiday keeps its own summary.
    it "always adds holidays as all-day events" do
      expect(builder.university_events.sole).to have_attributes(source: holiday, summary: "Fall Break", all_day: true)
    end

    it "adds the selected categories when university event sync is on" do
      config.update!(sync_university_events: true, university_event_categories: %w[registration])
      registration = university_event(category: "registration", start_time: 1.week.from_now)

      expect(builder.university_events.map(&:source)).to contain_exactly(holiday, registration)
    end

    it "leaves out a selected category that no longer syncs" do
      config.update!(sync_university_events: true, university_event_categories: %w[registration campus_event])
      registration = university_event(category: "registration", start_time: 1.week.from_now)
      university_event(category: "campus_event", start_time: 1.week.from_now)

      expect(builder.university_events.map(&:source)).to contain_exactly(holiday, registration)
    end

    it "builds only past events for the backfill" do
      past = university_event(category: "holiday", start_time: 2.months.ago)

      expect(builder.university_events(time_scope: :past).map(&:source)).to eq([ past ])
    end

    it "gives the events that overlap a date range" do
      inside = university_event(category: "holiday", start_time: Time.zone.local(2026, 10, 12))
      university_event(category: "holiday", start_time: Time.zone.local(2027, 3, 1))

      expect(builder.university_events(time_scope: Date.new(2026, 9, 1)..Date.new(2026, 12, 20)).map(&:source))
        .to contain_exactly(inside, holiday)
    end
  end
end
