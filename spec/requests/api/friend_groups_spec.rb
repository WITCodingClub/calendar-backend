# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Friends::Groups", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def befriend(other = create(:user))
    create(:friendship, :accepted, requester: other, addressee: user)
    other
  end

  def add_to(group, friend)
    create(:friend_group_membership, friend_group: group, friendship: user.accepted_friendship_with(friend))
  end

  after { Flipper.disable(FeatureFlags::FRIEND_GROUPS) }

  def query_count
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  context "when the friend_groups flag is off" do
    it "answers 404 on every route" do
      group = create(:friend_group, user: user)

      get "/api/friends/groups", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Friend groups are not enabled")

      post "/api/friends/groups", params: { name: "Study group" }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      delete "/api/friends/groups/#{group.public_id}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(FriendGroup.exists?(group.id)).to be(true)
    end
  end

  context "when the friend_groups flag is on for the user" do
    before { Flipper.enable_actor(FeatureFlags::FRIEND_GROUPS, user) }

    it "requires a token" do
      get "/api/friends/groups"

      expect(response).to have_http_status(:unauthorized)
    end

    describe "GET /api/friends/groups" do
      it "lists the user's groups by name, with members" do
        friend = befriend(create(:user, first_name: "Grace", last_name: "Hopper"))
        study  = create(:friend_group, user: user, name: "Study group")
        create(:friend_group, user: user, name: "Roommates")
        create(:friend_group, name: "Someone else's group")
        add_to(study, friend)

        get "/api/friends/groups", headers: headers

        expect(response).to have_http_status(:ok)
        groups = response.parsed_body["groups"]
        expect(groups.pluck("name")).to eq([ "Roommates", "Study group" ])
        expect(groups.last).to include(
          "id"      => study.public_id,
          "members" => [ { "id" => friend.public_id, "name" => "Grace Hopper" } ]
        )
        expect(groups.last.keys).to contain_exactly("id", "name", "members", "expires_at", "created_at", "updated_at")
      end
    end

    describe "GET /api/friends/groups/:group_id" do
      it "shows one group" do
        group = create(:friend_group, user: user)

        get "/api/friends/groups/#{group.public_id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("group", "id")).to eq(group.public_id)
      end

      it "answers 404 for another user's group" do
        get "/api/friends/groups/#{create(:friend_group).public_id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq("Group not found")
      end
    end

    describe "POST /api/friends/groups" do
      it "creates a group" do
        expect {
          post "/api/friends/groups", params: { name: "Study group" }, headers: headers, as: :json
        }.to change(user.friend_groups, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["group"]).to include("name" => "Study group", "members" => [])
        expect(response.parsed_body.dig("group", "id")).to start_with("fgr_")
      end

      it "creates the group with its members in one request" do
        ada = befriend(create(:user, first_name: "Ada", last_name: "Lovelace"))
        grace = befriend(create(:user, first_name: "Grace", last_name: "Hopper"))

        post "/api/friends/groups", params: { name: "Study group", member_ids: [ grace.public_id, ada.public_id ] },
                                    headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig("group", "members").pluck("id")).to eq([ ada.public_id, grace.public_id ])
      end

      it "creates nothing and lists the bad ids when a member id is not a friend" do
        friend   = befriend
        stranger = create(:user)

        expect {
          post "/api/friends/groups", params: { name: "Study group", member_ids: [ friend.public_id, stranger.public_id, "usr_nope" ] },
                                      headers: headers, as: :json
        }.not_to change(FriendGroup, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["invalid_member_ids"]).to contain_exactly(stranger.public_id, "usr_nope")
        expect(response.parsed_body["error"]).to include(stranger.public_id)
      end

      it "creates nothing when the name is invalid and members are given" do
        friend = befriend

        expect {
          post "/api/friends/groups", params: { name: "x" * 51, member_ids: [ friend.public_id ] }, headers: headers, as: :json
        }.not_to change(FriendGroupMembership, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "treats a pending request as a bad id" do
        pending_user = create(:user)
        create(:friendship, requester: pending_user, addressee: user)

        post "/api/friends/groups", params: { name: "Study group", member_ids: [ pending_user.public_id ] },
                                    headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(user.friend_groups).to be_empty
      end

      it "answers 400 when member_ids is not a list" do
        post "/api/friends/groups", params: { name: "Study group", member_ids: "usr_abc" }, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(user.friend_groups).to be_empty
      end

      it "refuses a name the user already uses, in any case" do
        create(:friend_group, user: user, name: "Study group")

        post "/api/friends/groups", params: { name: "study GROUP" }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("Name has already been taken")
      end

      it "answers 400 without a name" do
        post "/api/friends/groups", params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "reads a date-only end date as the end of that day in America/New_York" do
        post "/api/friends/groups", params: { name: "Study group", expires_at: "2099-12-01" },
                                    headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig("group", "expires_at")).to eq("2099-12-01T23:59:59-05:00")
        expect(user.friend_groups.last.expires_at).to eq(Time.zone.parse("2099-12-01 23:59:59 -05:00"))
      end

      it "answers 400 for an end date with no UTC offset" do
        expect {
          post "/api/friends/groups", params: { name: "Study group", expires_at: "2099-12-01T12:00:00" },
                                      headers: headers, as: :json
        }.not_to change(FriendGroup, :count)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq(Api::FriendLookup::EXPIRES_AT_FORMAT_ERROR)
      end

      it "answers 422 for an end date in the past" do
        post "/api/friends/groups", params: { name: "Study group", expires_at: "2020-01-01" },
                                    headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("Expires at must be in the future")
      end

      it "uses the name of an expired group again" do
        old = create(:friend_group, :temporary, user: user, name: "Study group")

        travel 8.days do
          post "/api/friends/groups", params: { name: "Study group" }, headers: headers, as: :json
        end

        expect(response).to have_http_status(:created)
        expect(FriendGroup.exists?(old.id)).to be(false)
      end
    end

    describe "PATCH /api/friends/groups/:group_id" do
      it "renames the group" do
        group = create(:friend_group, user: user, name: "Study group")

        patch "/api/friends/groups/#{group.public_id}", params: { name: "Roommates" }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("group", "name")).to eq("Roommates")
        expect(group.reload.name).to eq("Roommates")
      end

      it "replaces the members and keeps the name when only member_ids is sent" do
        keep = befriend(create(:user, first_name: "Ada", last_name: "Lovelace"))
        drop = befriend(create(:user, first_name: "Bob", last_name: "Drop"))
        add_new = befriend(create(:user, first_name: "Grace", last_name: "Hopper"))
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group, keep)
        add_to(group, drop)

        patch "/api/friends/groups/#{group.public_id}", params: { member_ids: [ keep.public_id, add_new.public_id ] },
                                                        headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("group", "members").pluck("id")).to eq([ keep.public_id, add_new.public_id ])
        expect(group.reload.name).to eq("Study group")
        expect(user.friend_of?(drop)).to be(true)
      end

      it "applies the name and the members together" do
        friend = befriend
        group  = create(:friend_group, user: user, name: "Study group")

        patch "/api/friends/groups/#{group.public_id}", params: { name: "Roommates", member_ids: [ friend.public_id ] },
                                                        headers: headers, as: :json

        expect(group.reload.name).to eq("Roommates")
        expect(group.members).to eq([ friend ])
      end

      it "clears the members when member_ids is an empty list" do
        group = create(:friend_group, user: user)
        add_to(group, befriend)

        patch "/api/friends/groups/#{group.public_id}", params: { member_ids: [] }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(group.memberships.reload).to be_empty
      end

      it "ignores a repeated id" do
        friend = befriend
        group  = create(:friend_group, user: user)

        patch "/api/friends/groups/#{group.public_id}", params: { member_ids: [ friend.public_id, friend.public_id ] },
                                                        headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(group.memberships.reload.count).to eq(1)
      end

      it "changes nothing and lists the bad ids when one id is not a friend" do
        keep     = befriend
        other    = befriend
        stranger = create(:user)
        group    = create(:friend_group, user: user, name: "Study group")
        add_to(group, keep)

        patch "/api/friends/groups/#{group.public_id}",
              params: { name: "Roommates", member_ids: [ other.public_id, stranger.public_id ] },
              headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["invalid_member_ids"]).to eq([ stranger.public_id ])
        expect(group.reload.name).to eq("Study group")
        expect(group.members).to eq([ keep ])
      end

      it "changes nothing when the name is invalid" do
        keep  = befriend
        other = befriend
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group, keep)

        patch "/api/friends/groups/#{group.public_id}", params: { name: "x" * 51, member_ids: [ other.public_id ] },
                                                        headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(group.reload.members).to eq([ keep ])
      end

      it "does not accept another user's friend" do
        theirs = create(:user)
        create(:friendship, :accepted, requester: theirs, addressee: create(:user))
        group = create(:friend_group, user: user)

        patch "/api/friends/groups/#{group.public_id}", params: { member_ids: [ theirs.public_id ] },
                                                        headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(group.memberships.reload).to be_empty
      end

      it "answers 400 when neither name nor member_ids is sent" do
        group = create(:friend_group, user: user)

        patch "/api/friends/groups/#{group.public_id}", params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "answers 400 when member_ids holds something other than ids" do
        group = create(:friend_group, user: user)

        patch "/api/friends/groups/#{group.public_id}", params: { member_ids: [ { id: 1 } ] },
                                                        headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "runs the same number of queries to replace 2 members and to replace 8" do
        group = create(:friend_group, user: user)
        friends = Array.new(8) { befriend }
        patch "/api/friends/groups/#{group.public_id}", params: { member_ids: [ friends[0].public_id ] },
                                                        headers: headers, as: :json # warm up

        few = query_count do
          patch "/api/friends/groups/#{group.public_id}", params: { member_ids: friends.first(2).map(&:public_id) },
                                                          headers: headers, as: :json
        end
        many = query_count do
          patch "/api/friends/groups/#{group.public_id}", params: { member_ids: friends.map(&:public_id) },
                                                          headers: headers, as: :json
        end

        expect(response.parsed_body.dig("group", "members").size).to eq(8)
        expect(many).to eq(few)
      end

      it "lists groups in a fixed number of queries" do
        3.times { |i| add_to(create(:friend_group, user: user, name: "Group #{i}"), befriend) }
        get "/api/friends/groups", headers: headers # warm up

        few = query_count { get "/api/friends/groups", headers: headers }
        6.times { |i| add_to(create(:friend_group, user: user, name: "More #{i}"), befriend) }
        many = query_count { get "/api/friends/groups", headers: headers }

        expect(response.parsed_body["groups"].size).to eq(9)
        expect(many).to eq(few)
      end

      it "does not rename another user's group" do
        group = create(:friend_group, name: "Theirs")

        patch "/api/friends/groups/#{group.public_id}", params: { name: "Mine" }, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(group.reload.name).to eq("Theirs")
      end

      it "sets an end date when only expires_at is sent" do
        group = create(:friend_group, user: user, name: "Study group")

        patch "/api/friends/groups/#{group.public_id}", params: { expires_at: "2099-12-01T17:00:00Z" },
                                                        headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(group.reload.expires_at).to eq(Time.utc(2099, 12, 1, 17))
        expect(group.name).to eq("Study group")
      end

      it "removes the end date when expires_at is null" do
        group = create(:friend_group, :temporary, user: user)

        patch "/api/friends/groups/#{group.public_id}", params: { expires_at: nil }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("group", "expires_at")).to be_nil
        expect(group.reload.expires_at).to be_nil
      end

      it "keeps the end date when expires_at is not sent" do
        group = create(:friend_group, :temporary, user: user)

        expect {
          patch "/api/friends/groups/#{group.public_id}", params: { name: "Roommates" }, headers: headers, as: :json
        }.not_to(change { group.reload.expires_at })
      end

      it "answers 400 for an end date that is not a date" do
        group = create(:friend_group, :temporary, user: user)

        expect {
          patch "/api/friends/groups/#{group.public_id}", params: { expires_at: "next week" }, headers: headers, as: :json
        }.not_to(change { group.reload.expires_at })

        expect(response).to have_http_status(:bad_request)
      end

      it "answers 404 for an expired group" do
        group = create(:friend_group, :temporary, user: user)

        travel 8.days do
          patch "/api/friends/groups/#{group.public_id}", params: { expires_at: nil }, headers: headers, as: :json
        end

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "DELETE /api/friends/groups/:group_id" do
      it "deletes the group and its memberships, and keeps the friendship" do
        friend = befriend
        group  = create(:friend_group, user: user)
        add_to(group, friend)

        expect {
          delete "/api/friends/groups/#{group.public_id}", headers: headers
        }.to change(FriendGroupMembership, :count).by(-1)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("ok" => true)
        expect(FriendGroup.exists?(group.id)).to be(false)
        expect(user.friend_of?(friend)).to be(true)
      end

      it "does not delete another user's group" do
        group = create(:friend_group)

        delete "/api/friends/groups/#{group.public_id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(FriendGroup.exists?(group.id)).to be(true)
      end
    end

    describe "POST /api/friends/groups/:group_id/members" do
      let(:group) { create(:friend_group, user: user) }

      it "adds a friend" do
        friend = befriend

        post "/api/friends/groups/#{group.public_id}/members", params: { friend_id: friend.public_id },
                                                                headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig("group", "members").pluck("id")).to eq([ friend.public_id ])
      end

      it "answers 200 and changes nothing when the friend is already in the group" do
        friend = befriend
        add_to(group, friend)

        expect {
          post "/api/friends/groups/#{group.public_id}/members", params: { friend_id: friend.public_id },
                                                                  headers: headers, as: :json
        }.not_to change(FriendGroupMembership, :count)

        expect(response).to have_http_status(:ok)
      end

      it "refuses a user who is not a friend" do
        stranger = create(:user)
        create(:friendship, requester: user, addressee: create(:user))

        post "/api/friends/groups/#{group.public_id}/members", params: { friend_id: stranger.public_id },
                                                                headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq("Friend not found")
      end

      it "refuses a pending request" do
        pending_friend = create(:user)
        create(:friendship, requester: user, addressee: pending_friend)

        post "/api/friends/groups/#{group.public_id}/members", params: { friend_id: pending_friend.public_id },
                                                                headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "refuses the user" do
        post "/api/friends/groups/#{group.public_id}/members", params: { friend_id: user.public_id },
                                                                headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "does not add to another user's group" do
        friend      = befriend
        other_group = create(:friend_group, user: friend)

        post "/api/friends/groups/#{other_group.public_id}/members", params: { friend_id: friend.public_id },
                                                                      headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(other_group.memberships).to be_empty
      end
    end

    describe "DELETE /api/friends/groups/:group_id/members/:friend_id" do
      let(:group) { create(:friend_group, user: user) }

      it "removes the friend from the group and keeps the friendship" do
        friend = befriend
        add_to(group, friend)

        delete "/api/friends/groups/#{group.public_id}/members/#{friend.public_id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("group", "members")).to eq([])
        expect(user.friend_of?(friend)).to be(true)
      end

      it "answers 404 for a friend who is not in the group" do
        friend = befriend

        delete "/api/friends/groups/#{group.public_id}/members/#{friend.public_id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq("Friend is not in this group")
      end
    end
  end

  describe "GET /api/friends" do
    it "leaves out groups while the flag is off" do
      befriend

      get "/api/friends", headers: headers

      expect(response.parsed_body["friends"].first.keys).to contain_exactly("id", "name", "visibility", "expires_at",
                                                                          "expiry_proposal")
    end

    context "when the flag is on" do
      before { Flipper.enable_actor(FeatureFlags::FRIEND_GROUPS, user) }

      it "lists each friend's groups" do
        in_group = befriend
        alone    = befriend
        group    = create(:friend_group, user: user, name: "Study group")
        add_to(group, in_group)

        get "/api/friends", headers: headers

        friends = response.parsed_body["friends"].index_by { |friend| friend["id"] }
        expect(friends[in_group.public_id]["groups"]).to eq([ { "id" => group.public_id, "name" => "Study group" } ])
        expect(friends[alone.public_id]["groups"]).to eq([])
      end

      it "does not show another user's groups" do
        friend = befriend
        theirs = create(:friend_group, user: friend)
        create(:friend_group_membership, friend_group: theirs, friendship: user.accepted_friendship_with(friend))

        get "/api/friends", headers: headers

        expect(response.parsed_body["friends"].first["groups"]).to eq([])
      end

      it "runs the same number of queries for 2 friends and for 8" do
        group = create(:friend_group, user: user)
        2.times { add_to(group, befriend) }
        get "/api/friends", headers: headers # warm up the Flipper cache and the token lookup

        few = query_count { get "/api/friends", headers: headers }
        6.times { add_to(create(:friend_group, user: user), befriend) }
        many = query_count { get "/api/friends", headers: headers }

        expect(response.parsed_body["friends"].size).to eq(8)
        expect(many).to eq(few)
      end
    end
  end
end
