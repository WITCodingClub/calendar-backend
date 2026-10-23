# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: friend_meetings
#
#  id              :bigint           not null, primary key
#  cancelled_at    :datetime
#  end_time        :datetime         not null
#  frequency       :string           default("one_time"), not null
#  guest_email     :string
#  guest_name      :string
#  idempotency_key :string
#  invite_friends  :boolean          default(FALSE), not null
#  location        :string
#  repeat_days     :string           default([]), not null, is an Array
#  repeat_interval :integer          default(1), not null
#  repeat_until    :date
#  start_time      :datetime         not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_friend_meetings_unique_idempotency_key  (user_id,idempotency_key) UNIQUE WHERE (idempotency_key IS NOT NULL)
#  index_friend_meetings_on_term_id            (term_id)
#  index_friend_meetings_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe FriendMeeting do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.find_zone!("America/New_York") }

  describe "associations and validations" do
    subject { build(:friend_meeting) }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:term).optional }
    it { is_expected.to have_many(:friend_meeting_attendees).dependent(:delete_all) }
    it { is_expected.to have_many(:attendees).through(:friend_meeting_attendees).source(:user) }
    it { is_expected.to have_many(:calendar_events).dependent(:destroy) }
    it { is_expected.to have_many(:publications).class_name("FriendMeetingPublication").dependent(:delete_all) }
    it { is_expected.to validate_length_of(:idempotency_key).is_at_most(FriendMeeting::IDEMPOTENCY_KEY_MAX_LENGTH) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(FriendMeeting::TITLE_MAX_LENGTH) }
    it { is_expected.to validate_length_of(:location).is_at_most(FriendMeeting::TITLE_MAX_LENGTH) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it { is_expected.to validate_length_of(:guest_name).is_at_most(FriendMeeting::GUEST_NAME_MAX_LENGTH) }
    it { is_expected.to allow_value("guest@example.com", nil).for(:guest_email) }
    it { is_expected.not_to allow_value("not-an-email").for(:guest_email) }
    it { is_expected.to validate_numericality_of(:repeat_interval).only_integer.is_in(1..FriendMeeting::MAX_REPEAT_INTERVAL) }

    it do
      expect(subject).to define_enum_for(:frequency)
        .with_values(one_time: "one_time", daily: "daily", weekly: "weekly", monthly: "monthly")
        .backed_by_column_of_type(:string)
        .validating
    end

    context "when the meeting has a guest" do
      subject { build(:friend_meeting, :with_guest) }

      it { is_expected.to validate_presence_of(:guest_name) }
    end

    context "when the meeting repeats weekly" do
      subject { build(:friend_meeting, :weekly) }

      it { is_expected.to validate_presence_of(:term) }
      it { is_expected.to validate_presence_of(:repeat_until) }
    end
  end

  # These compare two columns, which no shoulda matcher covers.
  describe "time validations" do
    it "needs the end after the start" do
      meeting = build(:friend_meeting, end_time: 2.days.from_now, start_time: 2.days.from_now + 1.hour)

      expect(meeting).not_to be_valid
      expect(meeting.errors[:end_time]).to include("must be after the start time")
    end

    it "refuses a meeting longer than 12 hours" do
      start  = 2.days.from_now
      meeting = build(:friend_meeting, start_time: start, end_time: start + 13.hours)

      expect(meeting).not_to be_valid
      expect(meeting.errors[:end_time]).to include("must be no more than 12 hours after the start time")
    end

    it "needs repeat_until on or after the start date" do
      meeting = build(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 15, 15), repeat_until: Date.new(2026, 9, 14))

      expect(meeting).not_to be_valid
      expect(meeting.errors[:repeat_until]).to include("must be on or after the start date")
    end

    it "refuses a repeat_until more than a year after the start date" do
      meeting = build(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 15, 15), repeat_until: Date.new(2027, 9, 17))

      expect(meeting).not_to be_valid
      expect(meeting.errors[:repeat_until]).to include("must be no more than 366 days after the start date")
    end
  end

  # These depend on the frequency, which no shoulda matcher covers.
  describe "repeat_days validations" do
    it "accepts weekday names for a weekly meeting" do
      expect(build(:friend_meeting, :weekly, repeat_days: %w[monday friday])).to be_valid
    end

    it "refuses a name that is not a weekday" do
      meeting = build(:friend_meeting, :weekly, repeat_days: %w[monday funday])

      expect(meeting).not_to be_valid
      expect(meeting.errors[:repeat_days].first).to start_with("must list only sunday, monday")
    end

    it "refuses days on a meeting that is not weekly" do
      meeting = build(:friend_meeting, :weekly, frequency: "daily", repeat_days: %w[monday])

      expect(meeting).not_to be_valid
      expect(meeting.errors[:repeat_days]).to include("can be set only for a weekly meeting")
    end
  end

  describe "#recurrence" do
    it "is nil for a one-time meeting" do
      expect(build(:friend_meeting).recurrence).to be_nil
    end

    it "repeats on the local start day until the end of the last day, in UTC" do
      meeting = build(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 15, 21), end_time: zone.local(2026, 9, 15, 22),
                                                repeat_until: Date.new(2026, 12, 18))

      # 21:00 Eastern on a Tuesday is Wednesday in UTC, so BYDAY must use the
      # local day. UNTIL is 23:59:59 Eastern on the last day.
      expect(meeting.recurrence).to eq([ "RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20261219T045959Z" ])
    end

    def repeating(**attributes)
      build(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 15, 15), end_time: zone.local(2026, 9, 15, 16),
                                      repeat_until: Date.new(2026, 12, 18), **attributes)
    end

    it "repeats every N days" do
      expect(repeating(frequency: "daily", repeat_interval: 3).recurrence)
        .to eq([ "RRULE:FREQ=DAILY;INTERVAL=3;UNTIL=20261219T045959Z" ])
    end

    it "repeats every other week on each picked day and the start day, with weeks that start on Sunday" do
      expect(repeating(repeat_interval: 2, repeat_days: %w[thursday sunday]).recurrence)
        .to eq([ "RRULE:FREQ=WEEKLY;INTERVAL=2;WKST=SU;BYDAY=SU,TU,TH;UNTIL=20261219T045959Z" ])
    end

    it "repeats monthly on the same weekday of the month" do
      # 2026-09-15 is the third Tuesday of September.
      expect(repeating(frequency: "monthly").recurrence).to eq([ "RRULE:FREQ=MONTHLY;BYDAY=3TU;UNTIL=20261219T045959Z" ])
    end

    it "repeats monthly on the last weekday when the start is the fifth one" do
      # 2026-09-29 is the fifth Tuesday of September.
      meeting = repeating(frequency: "monthly", start_time: zone.local(2026, 9, 29, 15), end_time: zone.local(2026, 9, 29, 16))

      expect(meeting.recurrence).to eq([ "RRULE:FREQ=MONTHLY;BYDAY=-1TU;UNTIL=20261219T045959Z" ])
    end
  end

  describe "#weekdays" do
    it "is the start day for a weekly meeting with no picked days" do
      expect(build(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 15, 15)).weekdays).to eq(%w[tuesday])
    end

    it "is empty for a meeting that is not weekly" do
      expect(build(:friend_meeting).weekdays).to eq([])
    end
  end

  describe "#event_data" do
    it "has the shape of a course event" do
      meeting = build(:friend_meeting, title: "Synthetic Study Group", location: "")

      expect(meeting.event_data).to include(summary: "Synthetic Study Group", location: nil, recurrence: nil, all_day: false,
                                            start_time: meeting.start_time, end_time: meeting.end_time)
    end
  end

  describe "#invitees" do
    let(:meeting) { create(:friend_meeting) }
    let(:friend)  { create(:user) }

    before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

    it "is empty when the person did not ask to invite friends" do
      expect(meeting.invitees).to eq([])
    end

    it "lists the friends when the person asked to invite them" do
      meeting.update!(invite_friends: true)

      expect(meeting.invitees).to eq([ friend ])
    end

    it "always lists the guest from a meeting link, after any friends" do
      meeting.update!(invite_friends: true, guest_name: "Sample Guest", guest_email: "guest@example.com")

      expect(meeting.invitees).to eq([ friend, FriendMeeting::Guest.new(email: "guest@example.com", full_name: "Sample Guest") ])
    end

    it "invites the guest even when the person did not ask to invite friends" do
      meeting.update!(guest_name: "Sample Guest", guest_email: "guest@example.com")

      expect(meeting.invitees.map(&:email)).to eq([ "guest@example.com" ])
    end
  end

  describe ".not_ended" do
    around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

    it "keeps a future meeting and a weekly meeting that still repeats, and drops the rest" do
      future  = create(:friend_meeting, start_time: zone.local(2026, 10, 8, 15), end_time: zone.local(2026, 10, 8, 16))
      ended   = create(:friend_meeting, start_time: zone.local(2026, 10, 1, 15), end_time: zone.local(2026, 10, 1, 16))
      ongoing = create(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 1, 15), end_time: zone.local(2026, 9, 1, 16),
                                                 repeat_until: Date.new(2026, 12, 18))
      over    = create(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 1, 15), end_time: zone.local(2026, 9, 1, 16),
                                                 repeat_until: Date.new(2026, 10, 6))

      expect(described_class.not_ended).to contain_exactly(future, ongoing)
      expect(described_class.not_ended).not_to include(ended, over)
    end
  end

  describe "#occurrences_between" do
    it "lists a one-time meeting once when it overlaps the range" do
      meeting = build(:friend_meeting, start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      expect(meeting.occurrences_between(zone.local(2026, 10, 14, 15, 30), zone.local(2026, 10, 15)))
        .to eq([ [ zone.local(2026, 10, 14, 15), zone.local(2026, 10, 14, 16) ] ])
      expect(meeting.occurrences_between(zone.local(2026, 10, 15), zone.local(2026, 10, 16))).to be_empty
    end

    it "lists each weekly occurrence until repeat_until, at the same local time" do
      meeting = build(:friend_meeting, frequency: "weekly", repeat_until: Date.new(2026, 11, 11),
                                       start_time: zone.local(2026, 10, 28, 15), end_time: zone.local(2026, 10, 28, 16))

      starts = meeting.occurrences_between(zone.local(2026, 10, 1), zone.local(2026, 12, 31)).map(&:first)

      expect(starts).to eq([ zone.local(2026, 10, 28, 15), zone.local(2026, 11, 4, 15), zone.local(2026, 11, 11, 15) ])
    end

    it "lists each occurrence of a meeting every other week on two days" do
      meeting = build(:friend_meeting, frequency: "weekly", repeat_interval: 2, repeat_days: %w[friday],
                                       repeat_until: Date.new(2026, 11, 13),
                                       start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      starts = meeting.occurrences_between(zone.local(2026, 10, 1), zone.local(2026, 12, 31)).map(&:first)

      expect(starts).to eq([ zone.local(2026, 10, 14, 15), zone.local(2026, 10, 16, 15),
                             zone.local(2026, 10, 28, 15), zone.local(2026, 10, 30, 15),
                             zone.local(2026, 11, 11, 15), zone.local(2026, 11, 13, 15) ])
    end

    it "lists each monthly occurrence on the same weekday of the month" do
      meeting = build(:friend_meeting, frequency: "monthly", repeat_until: Date.new(2026, 12, 31),
                                       start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      starts = meeting.occurrences_between(zone.local(2026, 10, 1), zone.local(2027, 1, 1)).map(&:first)

      expect(starts).to eq([ zone.local(2026, 10, 14, 15), zone.local(2026, 11, 11, 15), zone.local(2026, 12, 9, 15) ])
    end

    it "lists a daily meeting once on the fall-back day, at the first 01:30" do
      meeting = build(:friend_meeting, frequency: "daily", repeat_until: Date.new(2026, 11, 2),
                                       start_time: zone.local(2026, 10, 31, 1, 30), end_time: zone.local(2026, 10, 31, 2))

      starts = meeting.occurrences_between(zone.local(2026, 10, 31), zone.local(2026, 11, 3)).map(&:first)

      expect(starts.map { |time| time.in_time_zone(zone).strftime("%F %R") }).to eq([ "2026-10-31 01:30", "2026-11-01 01:30", "2026-11-02 01:30" ])
      expect(starts.second.utc_offset).to eq(-4.hours)
    end

    it "lists every third day for a daily meeting" do
      meeting = build(:friend_meeting, frequency: "daily", repeat_interval: 3, repeat_until: Date.new(2026, 10, 21),
                                       start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      starts = meeting.occurrences_between(zone.local(2026, 10, 1), zone.local(2026, 11, 1)).map(&:first)

      expect(starts).to eq([ zone.local(2026, 10, 14, 15), zone.local(2026, 10, 17, 15), zone.local(2026, 10, 20, 15) ])
    end
  end

  describe "scopes" do
    let(:owner)  { create(:user) }
    let(:friend) { create(:user) }

    it "finds the meetings that invited a person, and leaves out cancelled ones with .live" do
      invited     = create(:friend_meeting, :invite_friends, user: owner)
      not_invited = create(:friend_meeting, user: owner)
      cancelled   = create(:friend_meeting, :invite_friends, :cancelled, user: owner)
      [ invited, not_invited, cancelled ].each { |m| create(:friend_meeting_attendee, friend_meeting: m, user: friend) }

      expect(described_class.inviting(friend)).to contain_exactly(invited, cancelled)
      expect(described_class.live.inviting(friend)).to contain_exactly(invited)
    end

    it "finds a weekly meeting that started before the range by its repeat_until" do
      travel_to(zone.local(2026, 10, 7, 12)) do
        weekly = create(:friend_meeting, :weekly, start_time: zone.local(2026, 9, 2, 15), end_time: zone.local(2026, 9, 2, 16),
                                                  repeat_until: Date.new(2026, 12, 18))
        create(:friend_meeting, start_time: zone.local(2026, 9, 2, 15), end_time: zone.local(2026, 9, 2, 16))

        expect(described_class.overlapping(zone.local(2026, 10, 12), zone.local(2026, 10, 19))).to contain_exactly(weekly)
      end
    end
  end
end
