# frozen_string_literal: true

require "rails_helper"

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
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(FriendMeeting::TITLE_MAX_LENGTH) }
    it { is_expected.to validate_length_of(:location).is_at_most(FriendMeeting::TITLE_MAX_LENGTH) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it { is_expected.to validate_length_of(:guest_name).is_at_most(FriendMeeting::GUEST_NAME_MAX_LENGTH) }
    it { is_expected.to allow_value("guest@example.com", nil).for(:guest_email) }
    it { is_expected.not_to allow_value("not-an-email").for(:guest_email) }

    it do
      expect(subject).to define_enum_for(:frequency)
        .with_values(one_time: "one_time", weekly: "weekly")
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
end
