# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingPolicy do
  let(:owner)    { create(:user) }
  let(:friend)   { create(:user) }
  let(:stranger) { create(:user) }
  let(:meeting)  { create(:friend_meeting, :invite_friends, user: owner) }

  before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

  def policy(user, record = meeting) = described_class.new(user, record)

  it "lets any signed-in person make and list meetings" do
    expect(policy(stranger, FriendMeeting)).to have_attributes(create?: true, index?: true)
    expect(policy(nil, FriendMeeting)).to have_attributes(create?: false, index?: false)
  end

  it "lets the owner see, change, and delete the meeting" do
    expect(policy(owner)).to have_attributes(show?: true, update?: true, destroy?: true)
  end

  it "lets an invited friend only see the meeting" do
    expect(policy(friend)).to have_attributes(show?: true, update?: false, destroy?: false)
  end

  it "hides the meeting from a friend that the owner did not invite" do
    meeting.update!(invite_friends: false)

    expect(policy(friend).show?).to be(false)
  end

  it "gives a stranger nothing" do
    expect(policy(stranger)).to have_attributes(show?: false, update?: false, destroy?: false)
  end

  it "gives no one a cancelled meeting" do
    meeting.update!(cancelled_at: Time.current)

    expect(policy(owner)).to have_attributes(show?: false, update?: false, destroy?: false)
    expect(policy(friend).show?).to be(false)
  end

  describe FriendMeetingPolicy::Scope do
    it "holds the person's own meetings and the ones that invited them" do
      own_other = create(:friend_meeting, user: friend)
      create(:friend_meeting, user: stranger)
      create(:friend_meeting, :cancelled, user: friend)

      expect(described_class.new(friend, FriendMeeting).resolve).to contain_exactly(meeting, own_other)
      expect(described_class.new(nil, FriendMeeting).resolve).to be_empty
    end
  end
end
