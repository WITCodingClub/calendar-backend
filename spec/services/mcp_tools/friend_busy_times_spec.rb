# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::FriendBusyTimes do
  let(:user)   { create(:user) }
  let(:friend) { create(:user) }

  def call(friend_id) = described_class.call(server_context: mcp_context(user), friend_id: friend_id,
                                             start_date: "2026-12-17", end_date: "2026-12-17")

  context "when the friend shares availability only" do
    before do
      friendship = create(:friendship, :accepted, requester: user, addressee: friend)
      friendship.update_visibility_for!(friend, :availability_only)
    end

    it "lists the friend's busy blocks" do
      exam = create(:final_exam, course: create(:course))
      create(:enrollment, user: friend, course: exam.course)

      result = call(friend.public_id)

      expect(result.structured_content[:friend]).to eq(id: friend.public_id, name: friend.full_name)
      expect(result.structured_content[:busy].size).to eq(1)
    end
  end

  context "when the friend shares the full schedule" do
    before { create(:friendship, :accepted, requester: user, addressee: friend) }

    after { Flipper.disable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY) }

    it "waits for the availability flag, the same as the API" do
      expect(call(friend.public_id).content.first[:text]).to eq("Busy times for this friend are not available yet.")
    end

    it "lists the busy blocks once the flag is on" do
      Flipper.enable_actor(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, user)

      expect(call(friend.public_id).error?).to be(false)
    end
  end

  it "refuses someone who is not a friend" do
    result = call(friend.public_id)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("You are not friends with #{friend.public_id}")
  end

  it "refuses an expired friendship with a plain message" do
    friendship = create(:friendship, :accepted, :temporary, requester: user, addressee: friend)
    friendship.update_visibility_for!(friend, :availability_only)
    allow(Friendship).to receive(:accepted_between).and_return(friendship)
    allow(friendship).to receive(:expired?).and_return(true)

    expect(call(friend.public_id).content.first[:text]).to eq("You do not have access to that.")
  end

  it "refuses a pending request" do
    create(:friendship, requester: user, addressee: friend)

    expect(call(friend.public_id).error?).to be(true)
  end
end
