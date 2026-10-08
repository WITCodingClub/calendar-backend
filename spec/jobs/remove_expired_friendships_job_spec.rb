# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoveExpiredFriendshipsJob do
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
end
