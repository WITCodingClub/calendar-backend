# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingUpdater do
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
      .to have_enqueued_job(FriendMeetingUpdateJob).with(meeting)

    expect(meeting.reload).to have_attributes(title: "Synthetic Review", location: nil, start_time: zone.local(2026, 10, 14, 15))
    expect(meeting.publications.order(:id).pluck(:provider, :status)).to eq([ %w[google queued], %w[ics published] ])
  end

  it "starts no job for a meeting that is only in the ICS feed" do
    feed_only = create(:friend_meeting, destinations: %w[ics])

    expect { described_class.call(meeting: feed_only, changes: { title: "Synthetic Review" }) }
      .not_to have_enqueued_job(FriendMeetingUpdateJob)
  end

  it "starts no job when nothing changed" do
    expect { described_class.call(meeting: meeting, changes: { title: "Synthetic Study Group" }) }
      .not_to have_enqueued_job(FriendMeetingUpdateJob)
  end

  it "moves a weekly meeting to the term that holds its new first day" do
    fall   = create(:term, start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18))
    spring = create(:term, start_date: Date.new(2027, 1, 11), end_date: Date.new(2027, 4, 30))
    weekly = create(:friend_meeting, frequency: "weekly", term: fall, repeat_until: fall.end_date,
                                     start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16))

    described_class.call(meeting: weekly, changes: { start_time: "2027-01-13T15:00:00-05:00", end_time: "2027-01-13T16:00:00-05:00" })

    expect(weekly.reload).to have_attributes(term: spring, repeat_until: Date.new(2027, 4, 30))
  end

  it "refuses an empty change and a time without an offset" do
    expect { described_class.call(meeting: meeting, changes: {}) }.to raise_error(FriendMeetingCreator::Error, /at least one/)
    expect { described_class.call(meeting: meeting, changes: { start_time: "2026-10-14T15:00:00" }) }
      .to raise_error(FriendMeetingCreator::Error, /UTC offset/)
  end
end
