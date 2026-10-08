# frozen_string_literal: true

require "rails_helper"

RSpec.describe BusyBlocks do
  let(:user)   { create(:user) }
  let(:term)   { create(:term) }
  # Monday 2026-10-05 to Sunday 2026-10-11, inside the course dates.
  let(:monday) { Date.new(2026, 10, 5) }
  let(:sunday) { Date.new(2026, 10, 11) }

  def enroll(day_of_week:, begin_time:, end_time:, **course_attrs)
    course = create(:course, term: term, **course_attrs)
    create(:course_meeting_time, course: course, day_of_week: day_of_week, begin_time: begin_time, end_time: end_time)
    create(:enrollment, user: user, course: course)
    course
  end

  def blocks(from: monday, to: sunday)
    described_class.new(user, from: from, to: to).call.map { |b| [ b.date.iso8601, b.start, b.end ] }
  end

  it "lists one block for each class meeting in the range" do
    enroll(day_of_week: :monday, begin_time: 900, end_time: 1015)
    enroll(day_of_week: :wednesday, begin_time: 1300, end_time: 1445)

    expect(blocks).to eq([
      [ "2026-10-05", "09:00", "10:15" ],
      [ "2026-10-07", "13:00", "14:45" ]
    ])
  end

  it "repeats a weekly class on each matching date" do
    enroll(day_of_week: :tuesday, begin_time: 800, end_time: 850)

    expect(blocks(from: monday, to: monday + 13).map(&:first)).to eq(%w[2026-10-06 2026-10-13])
  end

  it "merges blocks on one date that overlap or touch" do
    enroll(day_of_week: :monday, begin_time: 900, end_time: 1015)
    enroll(day_of_week: :monday, begin_time: 1000, end_time: 1100)
    enroll(day_of_week: :monday, begin_time: 1100, end_time: 1150)
    enroll(day_of_week: :monday, begin_time: 1400, end_time: 1500)

    expect(blocks).to eq([
      [ "2026-10-05", "09:00", "11:50" ],
      [ "2026-10-05", "14:00", "15:00" ]
    ])
  end

  it "leaves out dates outside the class's start and end dates" do
    enroll(day_of_week: :monday, begin_time: 900, end_time: 1015,
           start_date: Date.new(2026, 10, 12), end_date: Date.new(2026, 12, 15))

    expect(blocks(from: monday, to: monday + 7).map(&:first)).to eq(%w[2026-10-12])
  end

  it "leaves out other users' classes" do
    other = create(:course, term: term)
    create(:course_meeting_time, course: other, day_of_week: :monday)
    create(:enrollment, course: other)

    expect(blocks).to be_empty
  end

  it "gives each block its weekday" do
    enroll(day_of_week: :friday, begin_time: 900, end_time: 1000)

    expect(described_class.new(user, from: monday, to: sunday).call.map(&:weekday)).to eq(%w[friday])
  end

  it "runs one query for each source (meetings, no-class days, finals, friend meetings), however many classes there are" do
    3.times { |i| enroll(day_of_week: :monday, begin_time: 900 + (i * 200), end_time: 1000 + (i * 200)) }

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.new(user, from: monday, to: sunday).call
    end

    expect(queries.length).to eq(4)
    expect(queries.grep(/course_meeting_times/).length).to eq(1)
  end

  it "refuses a range that ends before it starts" do
    expect { described_class.new(user, from: sunday, to: monday) }.to raise_error(ArgumentError)
  end

  it "refuses a range longer than MAX_DAYS" do
    expect {
      described_class.new(user, from: monday, to: monday + described_class::MAX_DAYS)
    }.to raise_error(ArgumentError)
  end

  describe "no-class days" do
    before { enroll(day_of_week: :monday, begin_time: 900, end_time: 1015) }

    it "removes meetings on a holiday" do
      create(:university_calendar_event, category: "holiday",
                                         start_time: Time.zone.local(2026, 10, 12), end_time: Time.zone.local(2026, 10, 12, 23))

      expect(blocks(from: monday, to: monday + 7).map(&:first)).to eq(%w[2026-10-05])
    end

    it "removes meetings on each day of a multi-day break" do
      create(:university_calendar_event, category: "study_day",
                                         start_time: Time.zone.local(2026, 10, 5), end_time: Time.zone.local(2026, 10, 9))

      expect(blocks).to eq([])
    end

    it "keeps meetings on a day with an event of another category" do
      create(:university_calendar_event, category: "campus_event",
                                         start_time: Time.zone.local(2026, 10, 5), end_time: Time.zone.local(2026, 10, 5, 12))

      expect(blocks.length).to eq(1)
    end
  end

  describe "final exams" do
    let(:course) { enroll(day_of_week: :monday, begin_time: 900, end_time: 1015) }

    it "adds the final exam of an enrolled course" do
      create(:final_exam, term: term, course: course, exam_date: Date.new(2026, 10, 8), start_time: 1300, end_time: 1500)

      expect(blocks).to include([ "2026-10-08", "13:00", "15:00" ])
    end

    it "keeps the final exam on a finals-period day with no classes" do
      create(:university_calendar_event, category: "finals",
                                         start_time: Time.zone.local(2026, 10, 5), end_time: Time.zone.local(2026, 10, 9))
      create(:final_exam, term: term, course: course, exam_date: Date.new(2026, 10, 8), start_time: 1300, end_time: 1500)

      expect(blocks).to eq([ [ "2026-10-08", "13:00", "15:00" ] ])
    end

    it "ignores the final exam of a course the user is not enrolled in" do
      create(:final_exam, term: term, course: create(:course, term: term), exam_date: Date.new(2026, 10, 8))

      expect(blocks).to eq([])
    end

    it "ignores a final exam outside the range" do
      create(:final_exam, term: term, course: course, exam_date: Date.new(2026, 12, 17))

      expect(blocks.map(&:first)).to eq(%w[2026-10-05])
    end
  end

  describe ".sources" do
    it "includes the busy time of a source that is added to the list" do
      extra = Class.new do
        def self.call(_user, from, _to) = [ BusyBlocks::Interval.new(date: from, begin_time: 1800, end_time: 1900) ]
      end
      allow(described_class).to receive(:sources).and_return([ extra ])

      expect(blocks).to eq([ [ "2026-10-05", "18:00", "19:00" ] ])
    end
  end

  describe "friend meetings" do
    let(:zone) { Time.zone }

    it "adds a meeting that the user owns" do
      create(:friend_meeting, user: user, start_time: zone.local(2026, 10, 6, 15), end_time: zone.local(2026, 10, 6, 16, 30))

      expect(blocks).to eq([ [ "2026-10-06", "15:00", "16:30" ] ])
    end

    it "adds a meeting that invited the user" do
      meeting = create(:friend_meeting, :invite_friends, start_time: zone.local(2026, 10, 7, 12), end_time: zone.local(2026, 10, 7, 13))
      create(:friend_meeting_attendee, friend_meeting: meeting, user: user)

      expect(blocks).to eq([ [ "2026-10-07", "12:00", "13:00" ] ])
    end

    it "ignores a meeting that lists the user but sent no invitations" do
      meeting = create(:friend_meeting, start_time: zone.local(2026, 10, 7, 12), end_time: zone.local(2026, 10, 7, 13))
      create(:friend_meeting_attendee, friend_meeting: meeting, user: user)

      expect(blocks).to be_empty
    end

    it "ignores a cancelled meeting" do
      create(:friend_meeting, :cancelled, user: user, start_time: zone.local(2026, 10, 6, 15), end_time: zone.local(2026, 10, 6, 16))

      expect(blocks).to be_empty
    end

    it "repeats a weekly meeting on each week until repeat_until" do
      create(:friend_meeting, :weekly, user: user, start_time: zone.local(2026, 10, 1, 18), end_time: zone.local(2026, 10, 1, 19),
                                       repeat_until: Date.new(2026, 10, 15))

      expect(blocks(from: monday, to: monday + 20).map(&:first)).to eq(%w[2026-10-08 2026-10-15])
    end

    it "keeps a meeting on a day with no classes" do
      create(:university_calendar_event, category: "holiday",
                                         start_time: zone.local(2026, 10, 6), end_time: zone.local(2026, 10, 6, 23))
      create(:friend_meeting, user: user, start_time: zone.local(2026, 10, 6, 15), end_time: zone.local(2026, 10, 6, 16))

      expect(blocks).to eq([ [ "2026-10-06", "15:00", "16:00" ] ])
    end

    it "splits a meeting that goes past midnight across both dates" do
      create(:friend_meeting, user: user, start_time: zone.local(2026, 10, 6, 23), end_time: zone.local(2026, 10, 7, 1))

      expect(blocks).to eq([ [ "2026-10-06", "23:00", "24:00" ], [ "2026-10-07", "00:00", "01:00" ] ])
    end

    it "merges a meeting with a class that it overlaps" do
      enroll(day_of_week: :monday, begin_time: 900, end_time: 1015)
      create(:friend_meeting, user: user, start_time: zone.local(2026, 10, 5, 10), end_time: zone.local(2026, 10, 5, 11))

      expect(blocks).to eq([ [ "2026-10-05", "09:00", "11:00" ] ])
    end
  end
end
