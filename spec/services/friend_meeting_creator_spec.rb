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

  it "makes a one-time meeting with the friends and starts the publish job" do
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
