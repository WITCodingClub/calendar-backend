# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin user friends", type: :request do
  let(:admin)  { create(:user, :super_admin) }
  let(:user)   { create(:user) }
  let(:friend) { create(:user) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    sign_in admin
  end

  describe "POST /admin/users/:id/add_friend" do
    it "replaces an expired friendship with a new permanent one" do
      old = create(:friendship, :accepted, :temporary, requester: user, addressee: friend)
      old.update_column(:expires_at, 1.minute.ago)

      post add_friend_admin_user_path(user), params: { friend_id: friend.public_id }

      expect(flash[:notice]).to eq("Added #{friend.full_name} as a friend.")
      expect(Friendship.exists?(old.id)).to be(false)
      expect(user.friends).to contain_exactly(friend)
      expect(user.accepted_friendship_with(friend).expires_at).to be_nil
    end

    it "still reports an unexpired friend" do
      create(:friendship, :accepted, :temporary, requester: user, addressee: friend)

      post add_friend_admin_user_path(user), params: { friend_id: friend.public_id }

      expect(flash[:alert]).to eq("#{friend.full_name} is already a friend.")
    end
  end
end
