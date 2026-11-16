# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::ExpiredRecordsJob do
  include ActiveSupport::Testing::TimeHelpers

  it "deletes expired friendships and requests, and keeps the rest" do
    permanent = create(:friendship, :accepted)
    later     = create(:friendship, :accepted, expires_at: 30.days.from_now)
    create(:friendship, :accepted, :temporary)
    create(:friendship, :temporary)

    travel 8.days do
      expect(described_class.perform_now).to include("Friendship" => 2)
    end

    expect(Friendship.all).to contain_exactly(permanent, later)
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

  it "deletes expired groups with their memberships, and keeps the friendships" do
    permanent  = create(:friend_group)
    group      = create(:friend_group, :temporary, :with_members)
    friendship = group.friendships.first

    travel 8.days do
      expect(described_class.perform_now).to include("FriendGroup" => 1)
    end

    expect(FriendGroup.all).to contain_exactly(permanent)
    expect(FriendGroupMembership.where(friend_group_id: group.id)).to be_empty
    expect(Friendship.exists?(friendship.id)).to be(true)
  end

  it "deletes expired passkey handoffs and WebAuthn challenges" do
    stale = WebauthnChallenge.issue!(challenge: "old", purpose: "authentication")
    PasskeyHandoff.issue!(user: create(:user), purpose: "session")

    travel 10.minutes do
      fresh = WebauthnChallenge.issue!(challenge: "new", purpose: "authentication")

      expect(described_class.perform_now).to include("WebauthnChallenge" => 1, "PasskeyHandoff" => 1)
      expect(WebauthnChallenge.all).to contain_exactly(fresh)
    end

    expect(WebauthnChallenge.exists?(stale.id)).to be(false)
  end

  it "keeps the old job names for jobs already in the queue" do
    expect(Friendships::RemoveExpiredJob).to eq(described_class)
    expect(FriendGroups::RemoveExpiredJob).to eq(described_class)
  end
end
