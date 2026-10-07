# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingLinkSlots do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)     { Time.zone }
  let(:owner)    { create(:user) }
  let(:term)     { create(:term) }
  # Thursday 2026-10-08 to Monday 2026-10-12.
  let(:thursday) { Date.new(2026, 10, 8) }
  let(:link)     { create(:meeting_link, user: owner, starts_on: thursday, ends_on: thursday + 4, duration_minutes: 60) }

  # Wednesday 2026-10-07, noon.
  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  def enroll(user, day_of_week:, begin_time:, end_time:)
    course = create(:course, term: term)
    create(:course_meeting_time, course: course, day_of_week: day_of_week, begin_time: begin_time, end_time: end_time)
    create(:enrollment, user: user, course: course)
  end

  def starts_on(date, guest: nil)
    described_class.new(link, guest: guest).call.select { |slot| slot.date == date }.map { |slot| slot.start_time.strftime("%H:%M") }
  end

  it "offers each half hour on weekdays, from 08:00 to the last start that ends by 21:00" do
    slots = described_class.new(link).call

    expect(slots.map(&:date).uniq).to eq([ thursday, thursday + 1, thursday + 4 ])
    expect(starts_on(thursday).first(3)).to eq(%w[08:00 08:30 09:00])
    expect(starts_on(thursday).last).to eq("20:00")
    expect(slots.first.end_time - slots.first.start_time).to eq(1.hour)
  end

  it "leaves out a time that overlaps a class, and keeps one that only touches it" do
    enroll(owner, day_of_week: :thursday, begin_time: 900, end_time: 1015)

    expect(starts_on(thursday).first(3)).to eq(%w[08:00 10:30 11:00])
  end

  it "leaves out a time that overlaps one of the owner's friend meetings" do
    create(:friend_meeting, user: owner, start_time: zone.local(2026, 10, 9, 8), end_time: zone.local(2026, 10, 9, 9))

    expect(starts_on(thursday + 1).first).to eq("09:00")
  end

  it "leaves out a friend meeting that the owner was added to, on each week it repeats" do
    meeting = create(:friend_meeting, :weekly, start_time: zone.local(2026, 10, 1, 8), end_time: zone.local(2026, 10, 1, 9),
                                               repeat_until: Date.new(2026, 12, 1))
    create(:friend_meeting_attendee, friend_meeting: meeting, user: owner)

    expect(starts_on(thursday).first).to eq("09:00")
  end

  it "with a signed-in guest, offers only the times when both people are free" do
    guest = create(:user)
    enroll(guest, day_of_week: :thursday, begin_time: 800, end_time: 1150)

    expect(starts_on(thursday, guest: guest).first).to eq("12:00")
    expect(starts_on(thursday).first).to eq("08:00")
  end

  it "ignores the guest when the guest is the owner" do
    expect(described_class.new(link, guest: owner).call).to eq(described_class.new(link).call)
  end

  it "gives no time that starts within an hour from now" do
    today_link = create(:meeting_link, user: owner, starts_on: Date.new(2026, 10, 7), ends_on: Date.new(2026, 10, 7), duration_minutes: 30)

    expect(described_class.new(today_link).call.first.start_time).to eq(zone.local(2026, 10, 7, 13))
  end

  describe "#find" do
    it "returns the free slot that starts at a time, and nil for a busy or unknown time" do
      enroll(owner, day_of_week: :thursday, begin_time: 900, end_time: 1015)
      finder = described_class.new(link)

      expect(finder.find(zone.local(2026, 10, 8, 8)).end_time).to eq(zone.local(2026, 10, 8, 9))
      expect(finder.find(zone.local(2026, 10, 8, 9))).to be_nil
      expect(finder.find(zone.local(2026, 10, 8, 8, 15))).to be_nil
    end
  end

  it "holds only times, so no course data can reach the page" do
    enroll(owner, day_of_week: :thursday, begin_time: 900, end_time: 1015)

    expect(described_class::Slot.members).to eq(%i[start_time end_time])
  end
end
