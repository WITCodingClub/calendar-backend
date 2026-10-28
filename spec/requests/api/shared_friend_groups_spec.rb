# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Friends::SharedGroups", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # The owner shares a group with two friends. The two members are not
  # friends with each other.
  let(:owner)   { create(:user, first_name: "Olive", last_name: "Owner") }
  let(:member)  { create(:user, first_name: "Mia", last_name: "Member") }
  let(:other)   { create(:user, first_name: "Otto", last_name: "Other") }
  let(:headers) { auth_headers_for(member) }

  let!(:member_friendship) { create(:friendship, :accepted, requester: owner, addressee: member) }
  let!(:other_friendship)  { create(:friendship, :accepted, requester: other, addressee: owner) }
  let!(:group) { group_with(member_friendship, other_friendship, shared: true, name: "Planning", color: "#33b679") }

  def group_with(*friendships, **attributes)
    create(:friend_group, user: owner, **attributes).tap do |group|
      friendships.each { |friendship| create(:friend_group_membership, friend_group: group, friendship: friendship) }
    end
  end

  def json = response.parsed_body

  after { Flipper.disable(FeatureFlags::FRIEND_GROUPS) }

  context "when the friend_groups flag is off" do
    it "answers 404 on every route" do
      get "/api/friends/shared_groups", headers: headers
      expect(response).to have_http_status(:not_found)

      get "/api/friends/groups/#{group.public_id}/busy_blocks", headers: headers
      expect(response).to have_http_status(:not_found)

      patch "/api/friends/shared_groups/#{group.public_id}", params: { status: "hidden" }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(group.membership_for(member)).to be_active
    end
  end

  context "when the flag is on for the owner and the viewer but not for another member" do
    before { [ owner, member ].each { |user| Flipper.enable_actor(FeatureFlags::FRIEND_GROUPS, user) } }

    it "leaves that member out of the group and its busy times" do
      get "/api/friends/shared_groups", headers: headers
      expect(json["groups"].first["members"].pluck("id")).to eq([ member.public_id ])

      get "/api/friends/groups/#{group.public_id}/busy_blocks", headers: headers
      expect(json["people"].pluck("id")).to eq([ owner.public_id, member.public_id ])
    end
  end

  context "when the friend_groups flag is on" do
    before { Flipper.enable(FeatureFlags::FRIEND_GROUPS) }

    describe "GET /api/friends/shared_groups" do
      it "lists the group with its owner and every member, also members who are not friends" do
        get "/api/friends/shared_groups", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["groups"].size).to eq(1)
        expect(json["groups"].first).to include(
          "id"      => group.public_id,
          "name"    => "Planning",
          "color"   => "#33b679",
          "owner"   => { "id" => owner.public_id, "name" => "Olive Owner" },
          "members" => [ { "id" => member.public_id, "name" => "Mia Member" },
                         { "id" => other.public_id, "name" => "Otto Other" } ]
        )
        expect(json["groups"].first["status"]).to eq("active")
        expect(json["groups"].first.keys).to contain_exactly("id", "name", "color", "status", "owner", "members",
                                                             "expires_at", "created_at", "updated_at")
      end

      it "leaves out a hidden group, and lists it with include_hidden" do
        group.membership_for(member).update!(status: :hidden)

        get "/api/friends/shared_groups", headers: headers
        expect(json["groups"]).to eq([])

        get "/api/friends/shared_groups", params: { include_hidden: true }, headers: headers
        expect(json["groups"].pluck("id", "status")).to eq([ [ group.public_id, "hidden" ] ])
      end

      it "still shows a member who hid the group to the other members" do
        group.membership_for(other).update!(status: :hidden)

        get "/api/friends/shared_groups", headers: headers

        expect(json["groups"].first["members"].pluck("id")).to eq([ member.public_id, other.public_id ])
      end

      it "leaves out a member who opted out" do
        group.membership_for(other).update!(status: :opted_out)

        get "/api/friends/shared_groups", headers: headers

        expect(json["groups"].first["members"].pluck("id")).to eq([ member.public_id ])
      end

      it "leaves out a group that the owner did not share" do
        group.update!(shared: false)

        get "/api/friends/shared_groups", headers: headers

        expect(json["groups"]).to eq([])
      end

      it "leaves out the user's own shared groups" do
        get "/api/friends/shared_groups", headers: auth_headers_for(owner)

        expect(json["groups"]).to eq([])
      end

      it "leaves out a shared group that the user is not in" do
        get "/api/friends/shared_groups", headers: auth_headers_for(create(:user))

        expect(json["groups"]).to eq([])
      end

      it "leaves out the group when the friendship with the owner ends" do
        member.remove_friend(owner)

        get "/api/friends/shared_groups", headers: headers

        expect(json["groups"]).to eq([])
      end

      it "leaves out an expired group" do
        group.update!(expires_at: 1.day.from_now)

        travel_to(2.days.from_now) do
          get "/api/friends/shared_groups", headers: auth_headers_for(member)
        end

        expect(json["groups"]).to eq([])
      end
    end

    describe "GET /api/friends/shared_groups/:group_id" do
      it "shows one shared group" do
        get "/api/friends/shared_groups/#{group.public_id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json.dig("group", "owner", "id")).to eq(owner.public_id)
      end

      it "answers 404 for a group that is not shared" do
        private_group = group_with(member_friendship)

        get "/api/friends/shared_groups/#{private_group.public_id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(json["error"]).to eq("Group not found")
      end
    end

    describe "PATCH /api/friends/shared_groups/:group_id" do
      def set_status(status, as: member)
        patch "/api/friends/shared_groups/#{group.public_id}", params: { status: status },
                                                                headers: auth_headers_for(as), as: :json
      end

      it "hides the group for the user and keeps the membership" do
        set_status("hidden")

        expect(response).to have_http_status(:ok)
        expect(json.dig("group", "status")).to eq("hidden")
        expect(group.membership_for(member)).to be_hidden
      end

      it "opts out, and opts back in" do
        set_status("opted_out")
        expect(group.membership_for(member)).to be_opted_out
        expect(member.friend_of?(owner)).to be(true)

        set_status("active")
        expect(group.membership_for(member)).to be_active
      end

      it "answers 422 for an unknown status" do
        set_status("gone")

        expect(response).to have_http_status(:unprocessable_content)
        expect(group.membership_for(member)).to be_active
      end

      it "answers 400 when status is not a string" do
        set_status([ "hidden" ])

        expect(response).to have_http_status(:bad_request)
      end

      it "answers 404 to the owner" do
        set_status("hidden", as: owner)

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "GET /api/friends/groups/:group_id/busy_blocks" do
      let(:params) { { start_date: "2026-10-14", end_date: "2026-10-14" } }

      before do
        create(:friend_meeting, user: other, start_time: Time.zone.local(2026, 10, 14, 15),
                                end_time: Time.zone.local(2026, 10, 14, 16))
      end

      it "gives a member the busy times of everyone, also a member who is not a friend" do
        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json).to include("group_id" => group.public_id, "start_date" => "2026-10-14", "end_date" => "2026-10-14")
        expect(json["people"].map { |person| person.values_at("id", "role") }).to eq(
          [ [ owner.public_id, "owner" ], [ member.public_id, "member" ], [ other.public_id, "member" ] ]
        )
        busy = json["people"].index_by { |person| person["id"] }.transform_values { |person| person["busy"] }
        expect(busy[other.public_id]).to eq([ { "date" => "2026-10-14", "weekday" => "wednesday",
                                                "start" => "15:00", "end" => "16:00" } ])
        expect(busy[owner.public_id]).to eq([])
      end

      it "leaves out a member who opted out, for the other members but not for the owner" do
        group.membership_for(other).update!(status: :opted_out)

        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: headers
        expect(json["people"].pluck("id")).to eq([ owner.public_id, member.public_id ])

        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: auth_headers_for(owner)
        expect(json["people"].pluck("id")).to include(other.public_id)
      end

      it "answers 403 to a member who opted out" do
        group.membership_for(member).update!(status: :opted_out)

        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:forbidden)
      end

      it "gives the owner the busy times of a group that is not shared" do
        group.update!(shared: false)

        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: auth_headers_for(owner)

        expect(response).to have_http_status(:ok)
        expect(json["people"].size).to eq(3)
      end

      it "answers 404 to a member of a group that is not shared" do
        group.update!(shared: false)

        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "answers 404 to a user who is not in the group" do
        get "/api/friends/groups/#{group.public_id}/busy_blocks", params: params, headers: auth_headers_for(create(:user))

        expect(response).to have_http_status(:not_found)
      end

      it "answers 400 for a range that is too long" do
        get "/api/friends/groups/#{group.public_id}/busy_blocks",
            params: { start_date: "2026-01-01", end_date: "2026-12-31" }, headers: headers

        expect(response).to have_http_status(:bad_request)
      end
    end

    describe "POST and PATCH /api/friends/groups with shared and color" do
      let(:owner_headers) { auth_headers_for(owner) }

      it "lists the members who opted out for the owner" do
        group.membership_for(other).update!(status: :opted_out)

        get "/api/friends/groups/#{group.public_id}", headers: owner_headers

        expect(json.dig("group", "opted_out_member_ids")).to eq([ other.public_id ])
        expect(json.dig("group", "members").pluck("id")).to include(other.public_id)
      end

      it "creates a shared group with any color" do
        post "/api/friends/groups", params: { name: "Suite", shared: true, color: "#1A2B3C" },
                                    headers: owner_headers, as: :json

        expect(response).to have_http_status(:created)
        expect(json["group"]).to include("shared" => true, "color" => "#1a2b3c")
      end

      it "stops sharing and clears the color" do
        patch "/api/friends/groups/#{group.public_id}", params: { shared: false, color: nil },
                                                        headers: owner_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(json["group"]).to include("shared" => false, "color" => nil)
        expect(FriendGroup.shared_with(member)).to be_empty
      end

      it "answers 422 for a color that is not #rrggbb" do
        patch "/api/friends/groups/#{group.public_id}", params: { color: "green" }, headers: owner_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(group.reload.color).to eq("#33b679")
      end

      it "answers 400 when shared is not true or false" do
        patch "/api/friends/groups/#{group.public_id}", params: { shared: "yes" }, headers: owner_headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(json["error"]).to eq("shared must be true or false")
      end
    end
  end
end
