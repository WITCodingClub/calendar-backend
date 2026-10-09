# frozen_string_literal: true

require "rails_helper"

RSpec.describe Friendships::RemoveExpiredJob do
  include ActiveSupport::Testing::TimeHelpers

  it "deletes expired friendships and requests, and keeps the rest" do
    permanent = create(:friendship, :accepted)
    later     = create(:friendship, :accepted, expires_at: 30.days.from_now)
    accepted  = create(:friendship, :accepted, :temporary)
    request   = create(:friendship, :temporary)

    travel 8.days do
      expect(described_class.perform_now).to eq(removed: 2)
    end

    expect(Friendship.all).to contain_exactly(permanent, later)
    expect(Friendship.exists?(accepted.id)).to be(false)
    expect(Friendship.exists?(request.id)).to be(false)
  end

  it "takes ex-friends off each other's meetings" do
    friendship = create(:friendship, :accepted, :temporary)
    meeting    = create(:friend_meeting, user: friendship.requester)
    create(:friend_meeting_attendee, friend_meeting: meeting, user: friendship.addressee)

    travel 8.days do
      described_class.perform_now
    end

    expect(meeting.friend_meeting_attendees.reload).to be_empty
  end

  it "keeps attendees of a request that was never accepted" do
    request = create(:friendship, :temporary)
    meeting = create(:friend_meeting, user: request.requester)
    create(:friend_meeting_attendee, friend_meeting: meeting, user: request.addressee)

    travel 8.days do
      described_class.perform_now
    end

    expect(meeting.friend_meeting_attendees.reload.size).to eq(1)
  end
end
