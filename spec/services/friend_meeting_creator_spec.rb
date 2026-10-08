# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingCreator do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)   { Time.find_zone!("America/New_York") }
  let(:user)   { create(:user) }
  let(:friend) { create(:user) }
  let(:term)   { create(:term, start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18)) }

  let(:attributes) do
    {
      user:       user,
      title:      "Synthetic Study Group",
      start_time: "2026-10-14T15:00:00-04:00",
      end_time:   "2026-10-14T16:00:00-04:00",
      friend_ids: [ friend.public_id ]
    }
  end

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  before { create(:friendship, :accepted, requester: user, addressee: friend) }

  def create_meeting(**overrides)
    described_class.call(**attributes, **overrides)
  end

  def connect_google
    credential = create(:oauth_credential, user: user)
    create(:course_calendar, oauth_credential: credential)
  end

  it "makes a one-time meeting with the friends and starts the publish job" do
    connect_google
    meeting = nil

    expect { meeting = create_meeting(location: " Synthetic Library ") }
      .to have_enqueued_job(FriendMeetingPublishJob)

    expect(meeting).to have_attributes(title: "Synthetic Study Group", location: "Synthetic Library", frequency: "one_time",
                                       start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16),
                                       invite_friends: false, term: nil, repeat_until: nil)
    expect(meeting.attendees).to eq([ friend ])
  end

  it "keeps the choice to invite the friends" do
    expect(create_meeting(invite_friends: "true")).to be_invite_friends
  end

  it "takes the id that the accept route returns, without the usr_ prefix" do
    meeting = create_meeting(friend_ids: [ friend.public_id.delete_prefix("usr_") ])

    expect(meeting.attendees).to eq([ friend ])
  end

  it "repeats a weekly meeting until the end of the term that holds its first day" do
    term

    meeting = create_meeting(frequency: "weekly")

    expect(meeting).to have_attributes(frequency: "weekly", term: term, repeat_until: Date.new(2026, 12, 18))
  end

  describe "destinations" do
    it "sends the meeting to every connected calendar and the ICS feed by default" do
      connect_google

      meeting = create_meeting(invite_friends: true)

      expect(meeting.publications.order(:id).map { |p| [ p.provider, p.status, p.sends_invitations ] })
        .to eq([ [ "google", "queued", true ], [ "ics", "published", false ] ])
    end

    it "makes only the ICS row and starts no job for a person who uses only the feed" do
      meeting = nil

      expect { meeting = create_meeting }.not_to have_enqueued_job(FriendMeetingPublishJob)
      expect(meeting.destinations).to eq([ "ics" ])
    end

    it "keeps the places that the person picked, in order" do
      connect_google

      meeting = create_meeting(destinations: [ "ICS", "google" ], invite_friends: true)

      expect(meeting.destinations).to eq(%w[ics google])
      expect(meeting.publication_for("google")).to be_sends_invitations
    end

    it "refuses a place that is not connected" do
      expect { create_meeting(destinations: [ "microsoft" ]) }
        .to raise_error(described_class::Error, "destinations can list only ics; not microsoft")
    end

    it "refuses an empty list" do
      expect { create_meeting(destinations: []) }.to raise_error(described_class::Error, /at least one place/)
    end
  end

  describe "idempotency key" do
    it "returns the first meeting for a retry with the same key, and makes nothing new" do
      connect_google
      first = create_meeting(idempotency_key: "synthetic-key-1", invite_friends: true)
      clear_enqueued_jobs

      retried = create_meeting(idempotency_key: "synthetic-key-1", invite_friends: true, title: "Changed")

      expect(retried).to eq(first)
      expect(retried).not_to be_previously_new_record
      expect(FriendMeeting.count).to eq(1)
      expect(enqueued_jobs).to be_empty
    end

    it "makes a new meeting for another key, or for another person with the same key" do
      create_meeting(idempotency_key: "synthetic-key-1")
      other = create(:user)
      create(:friendship, :accepted, requester: other, addressee: friend)

      create_meeting(idempotency_key: "synthetic-key-2")
      create_meeting(user: other, idempotency_key: "synthetic-key-1")

      expect(FriendMeeting.count).to eq(3)
    end

    it "returns the meeting that won a race for the same key" do
      first = create_meeting(idempotency_key: "synthetic-key-1")
      creator = described_class.new(**attributes, idempotency_key: "synthetic-key-1")
      allow(creator).to receive(:find_existing).and_return(nil, first)

      expect(creator.call).to eq(first)
    end
  end

  describe "requests that cannot become a meeting" do
    it "refuses a weekly meeting when no term holds its first day" do
      expect { create_meeting(frequency: "weekly") }.to raise_error(described_class::Error, /current term/)
    end

    it "refuses a weekly meeting when the term has no end date yet" do
      term.update!(end_date: nil)
      allow(Term).to receive(:current).and_return(term)

      expect { create_meeting(frequency: "weekly") }.to raise_error(described_class::Error, /current term/)
    end

    it "refuses an unknown frequency" do
      expect { create_meeting(frequency: "daily") }.to raise_error(described_class::Error, "frequency must be one_time or weekly")
    end

    it "refuses a person who is not a friend" do
      stranger = create(:user)

      expect { create_meeting(friend_ids: [ stranger.public_id ]) }
        .to raise_error(described_class::Error, "#{stranger.public_id} is not one of your accepted friends")
    end

    it "refuses a friend whose request is still pending" do
      pending_friend = create(:user)
      create(:friendship, requester: user, addressee: pending_friend)

      expect { create_meeting(friend_ids: [ pending_friend.public_id ]) }.to raise_error(described_class::Error, /accepted friends/)
    end

    it "needs at least one friend" do
      expect { create_meeting(friend_ids: [ "" ]) }.to raise_error(described_class::Error, /at least one friend/)
    end

    it "refuses too many friends" do
      ids = Array.new(FriendMeeting::MAX_ATTENDEES + 1) { |n| "usr_synthetic#{n}" }

      expect { create_meeting(friend_ids: ids) }.to raise_error(described_class::Error, /no more than/)
    end

    it "needs a time with a UTC offset" do
      expect { create_meeting(start_time: "2026-10-14T15:00:00") }
        .to raise_error(described_class::Error, "start_time must be an ISO 8601 time with a UTC offset")
    end

    it "refuses a time that is not ISO 8601" do
      expect { create_meeting(end_time: "next tuesday") }.to raise_error(described_class::Error, /end_time/)
    end

    it "raises RecordInvalid and saves nothing when the end is before the start" do
      expect { create_meeting(end_time: "2026-10-14T14:00:00-04:00") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(FriendMeeting.count).to eq(0)
      expect(enqueued_jobs).to be_empty
    end
  end
end
