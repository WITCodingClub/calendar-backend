# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::Updater do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.find_zone!("America/New_York") }
  let(:meeting) do
    create(:friend_meeting, title: "Synthetic Study Group", destinations: %w[google ics],
                            start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))
  end

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  it "changes only the fields it gets, queues the provider rows, and starts the update job" do
    meeting.publication_for("google").update!(status: "published")

    expect { described_class.call(meeting: meeting, changes: { "title" => " Synthetic Review ", "location" => "" }) }
      .to have_enqueued_job(FriendMeetings::UpdateJob).with(meeting)

    expect(meeting.reload).to have_attributes(title: "Synthetic Review", location: nil, start_time: zone.local(2026, 10, 14, 15))
    expect(meeting.publications.order(:id).pluck(:provider, :status)).to eq([ %w[google queued], %w[ics published] ])
  end

  it "starts no job for a meeting that is only in the ICS feed" do
    feed_only = create(:friend_meeting, destinations: %w[ics])

    expect { described_class.call(meeting: feed_only, changes: { title: "Synthetic Review" }) }
      .not_to have_enqueued_job(FriendMeetings::UpdateJob)
  end

  it "starts no job when nothing changed" do
    expect { described_class.call(meeting: meeting, changes: { title: "Synthetic Study Group" }) }
      .not_to have_enqueued_job(FriendMeetings::UpdateJob)
  end

  it "moves a weekly meeting to the term that holds its new first day" do
    fall   = create(:term, start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18))
    spring = create(:term, start_date: Date.new(2027, 1, 11), end_date: Date.new(2027, 4, 30))
    weekly = create(:friend_meeting, frequency: "weekly", term: fall, repeat_until: fall.end_date,
                                     start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

    described_class.call(meeting: weekly, changes: { start_time: "2027-01-13T15:00:00-05:00", end_time: "2027-01-13T16:00:00-05:00" })

    expect(weekly.reload).to have_attributes(term: spring, repeat_until: Date.new(2027, 4, 30))
  end

  it "keeps a repeat_until that the person picked when the meeting moves" do
    fall    = create(:term, start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18))
    monthly = create(:friend_meeting, frequency: "monthly", term: fall, repeat_until: Date.new(2027, 5, 1),
                                      start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

    described_class.call(meeting: monthly, changes: { start_time: "2026-10-21T15:00:00-04:00", end_time: "2026-10-21T16:00:00-04:00" })

    expect(monthly.reload).to have_attributes(term: fall, repeat_until: Date.new(2027, 5, 1))
  end

  describe "repeat options" do
    let!(:fall) { create(:term, start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18)) }

    def update(target, **changes)
      described_class.call(meeting: target, changes: changes)
    end

    it "makes a one-time meeting repeat until the end of the term, and starts the update job" do
      expect { update(meeting, frequency: "weekly", repeat_interval: "2", repeat_days: [ "Friday" ]) }
        .to have_enqueued_job(FriendMeetings::UpdateJob).with(meeting)

      expect(meeting.reload).to have_attributes(frequency: "weekly", repeat_interval: 2, repeat_days: %w[friday],
                                                term: fall, repeat_until: fall.end_date)
      expect(meeting.publications.calendars.pluck(:status)).to eq([ "queued" ])
    end

    it "changes only the interval and keeps the rest" do
      weekly = create(:friend_meeting, :weekly, term: fall, repeat_until: Date.new(2027, 2, 1), repeat_days: %w[friday],
                                                start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      update(weekly, repeat_interval: 3)

      expect(weekly.reload).to have_attributes(frequency: "weekly", repeat_interval: 3, repeat_days: %w[friday],
                                               repeat_until: Date.new(2027, 2, 1))
    end

    it "drops the days when a weekly meeting becomes monthly" do
      weekly = create(:friend_meeting, :weekly, term: fall, repeat_days: %w[friday], repeat_interval: 2,
                                                start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      update(weekly, frequency: "monthly")

      expect(weekly.reload).to have_attributes(frequency: "monthly", repeat_interval: 2, repeat_days: [])
    end

    it "sets a picked repeat_until, and goes back to the end of the term with nil" do
      weekly = create(:friend_meeting, :weekly, term: fall, repeat_until: fall.end_date,
                                                start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      update(weekly, repeat_until: "2027-03-01")
      expect(weekly.reload.repeat_until).to eq(Date.new(2027, 3, 1))

      update(weekly, repeat_until: nil)
      expect(weekly.reload.repeat_until).to eq(fall.end_date)
    end

    it "stops the repeats with one_time and clears the options" do
      weekly = create(:friend_meeting, :weekly, term: fall, repeat_interval: 2, repeat_days: %w[friday],
                                                start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

      update(weekly, frequency: "one_time")

      expect(weekly.reload).to have_attributes(frequency: "one_time", repeat_interval: 1, repeat_days: [], term: nil, repeat_until: nil)
      expect(weekly.recurrence).to be_nil
    end

    it "refuses repeat options for a one-time meeting, an unknown frequency, and a bad date" do
      expect { update(meeting, repeat_interval: 2) }.to raise_error(FriendMeetings::Creator::Error, /need a repeating frequency/)
      expect { update(meeting, frequency: "yearly") }.to raise_error(FriendMeetings::Creator::Error, /frequency must be one of/)
      expect { update(meeting, frequency: "daily", repeat_until: "soon") }
        .to raise_error(FriendMeetings::Creator::Error, "repeat_until must be an ISO 8601 date")
    end
  end

  it "refuses an empty change and a time without an offset" do
    expect { described_class.call(meeting: meeting, changes: {}) }.to raise_error(FriendMeetings::Creator::Error, /at least one/)
    expect { described_class.call(meeting: meeting, changes: { start_time: "2026-10-14T15:00:00" }) }
      .to raise_error(FriendMeetings::Creator::Error, /UTC offset/)
  end
end
