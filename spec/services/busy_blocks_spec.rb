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

  it "reads the schedule in one query, however many classes there are" do
    3.times { |i| enroll(day_of_week: :monday, begin_time: 900 + (i * 200), end_time: 1000 + (i * 200)) }

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.new(user, from: monday, to: sunday).call
    end

    expect(queries.length).to eq(1)
  end

  it "refuses a range that ends before it starts" do
    expect { described_class.new(user, from: sunday, to: monday) }.to raise_error(ArgumentError)
  end

  it "refuses a range longer than MAX_DAYS" do
    expect {
      described_class.new(user, from: monday, to: monday + described_class::MAX_DAYS)
    }.to raise_error(ArgumentError)
  end
end
