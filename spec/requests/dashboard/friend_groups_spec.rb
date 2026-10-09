# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard friend groups", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)   { create(:user, :with_processed_courses) }
  let(:friend) { create(:user, first_name: "Grace", last_name: "Hopper") }

  before do
    create(:friendship, :accepted, requester: friend, addressee: user)
    sign_in user
  end

  after { Flipper.disable(FeatureFlags::FRIEND_GROUPS) }

  def add_to(group, member = friend)
    create(:friend_group_membership, friend_group: group, friendship: user.accepted_friendship_with(member))
  end

  context "when the friend_groups flag is off" do
    it "does not show groups on the friends page" do
      create(:friend_group, user: user, name: "Study group")

      get dashboard_friends_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Study group")
      expect(response.body).not_to include("Create group")
    end

    it "answers 404 to the group actions" do
      group = create(:friend_group, user: user)

      post dashboard_friend_groups_path, params: { name: "Roommates" }
      expect(response).to have_http_status(:not_found)

      delete dashboard_friend_group_path(group.public_id)
      expect(response).to have_http_status(:not_found)

      post dashboard_friend_group_members_path(group.public_id), params: { friend_id: friend.public_id }
      expect(response).to have_http_status(:not_found)
      expect(group.memberships).to be_empty
    end
  end

  context "when the flag is on for the user" do
    before { Flipper.enable_actor(FeatureFlags::FRIEND_GROUPS, user) }

    describe "GET /dashboard/friends" do
      it "shows the groups, their members, and each friend's groups" do
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group)
        create(:friend_group, name: "Not my group")

        get dashboard_friends_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Create group")
        expect(response.body).to include("Study group")
        expect(response.body).to include("Remove Grace Hopper from Study group")
        expect(response.body).not_to include("Not my group")
        friend_row_groups = Nokogiri::HTML(response.body).css("ul[aria-label='Groups'] li").map(&:text)
        expect(friend_row_groups).to eq([ "Study group" ])
      end

      it "checks the boxes of the friends who are in the group" do
        other = create(:user, first_name: "Ada", last_name: "Lovelace")
        create(:friendship, :accepted, requester: user, addressee: other)
        group = create(:friend_group, user: user)
        add_to(group)

        get dashboard_friends_path

        doc = Nokogiri::HTML(response.body)
        checked = ->(who) { doc.at_css("input#group_#{group.public_id}_friend_#{who.public_id}")["checked"] }
        expect(checked.call(friend)).to be_present
        expect(checked.call(other)).to be_nil
      end

      it "shows the end date in the list and in the editor" do
        group = create(:friend_group, user: user, name: "Study group", expires_at: Time.zone.parse("2099-12-01 23:59:59"))

        get dashboard_friends_path

        expect(response.body).to include("Ends on December 01, 2099")
        expect(Nokogiri::HTML(response.body).at_css("input#group_#{group.public_id}_expires_on")["value"])
          .to eq("2099-12-01")
      end

      it "hides an expired group before the cleanup job removes it" do
        group = create(:friend_group, :temporary, user: user, name: "Old study group")
        add_to(group)

        travel 8.days do
          get dashboard_friends_path
        end

        expect(response.body).not_to include("Old study group")
      end
    end

    describe "POST /dashboard/friends/groups" do
      it "creates a group" do
        expect {
          post dashboard_friend_groups_path, params: { name: "Roommates" }
        }.to change(user.friend_groups, :count).by(1)

        expect(response).to redirect_to(dashboard_friends_path)
        expect(flash[:notice]).to eq("Group \"Roommates\" created.")
      end

      it "creates the group with its members in one request" do
        post dashboard_friend_groups_path, params: { name: "Roommates", member_ids: [ "", friend.public_id ] }

        expect(user.friend_groups.find_by(name: "Roommates").members).to eq([ friend ])
      end

      it "creates nothing when a member id is not a friend" do
        expect {
          post dashboard_friend_groups_path, params: { name: "Roommates", member_ids: [ create(:user).public_id ] }
        }.not_to change(FriendGroup, :count)

        expect(flash[:alert]).to include("not your friends")
      end

      it "reports an invalid name" do
        post dashboard_friend_groups_path, params: { name: "" }

        expect(response).to redirect_to(dashboard_friends_path)
        expect(flash[:alert]).to eq("Name can't be blank")
      end

      it "sets the end date to the end of that day in America/New_York" do
        post dashboard_friend_groups_path, params: { name: "Roommates", expires_on: "2099-12-01" }

        expect(user.friend_groups.find_by(name: "Roommates").expires_at)
          .to eq(Time.zone.parse("2099-12-01 23:59:59 -05:00"))
      end

      it "creates a group with no end date when the date field is empty" do
        post dashboard_friend_groups_path, params: { name: "Roommates", expires_on: "" }

        expect(user.friend_groups.find_by(name: "Roommates").expires_at).to be_nil
      end

      it "creates nothing for an end date that is not valid" do
        expect {
          post dashboard_friend_groups_path, params: { name: "Roommates", expires_on: "soon" }
        }.not_to change(FriendGroup, :count)

        expect(flash[:alert]).to eq("That end date is not valid.")
      end

      it "reports an end date in the past" do
        post dashboard_friend_groups_path, params: { name: "Roommates", expires_on: "2020-01-01" }

        expect(flash[:alert]).to eq("Expires at must be in the future")
      end
    end

    describe "PATCH /dashboard/friends/groups/:id" do
      it "renames the group and keeps the members when the form sends no member list" do
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group)

        patch dashboard_friend_group_path(group.public_id), params: { name: "Lab partners" }

        expect(group.reload.name).to eq("Lab partners")
        expect(group.members).to eq([ friend ])
        expect(flash[:notice]).to eq("Group saved.")
      end

      it "applies the name and the members together" do
        other = create(:user, first_name: "Ada", last_name: "Lovelace")
        create(:friendship, :accepted, requester: user, addressee: other)
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group)

        patch dashboard_friend_group_path(group.public_id),
              params: { name: "Lab partners", member_ids: [ "", other.public_id ] }

        expect(group.reload.name).to eq("Lab partners")
        expect(group.members).to eq([ other ])
      end

      it "clears the members when the form sends only the empty marker" do
        group = create(:friend_group, user: user)
        add_to(group)

        patch dashboard_friend_group_path(group.public_id), params: { name: group.name, member_ids: [ "" ] }

        expect(group.reload.members).to be_empty
      end

      it "changes nothing when one member id is not a friend" do
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group)

        patch dashboard_friend_group_path(group.public_id),
              params: { name: "Lab partners", member_ids: [ create(:user).public_id ] }

        expect(group.reload.name).to eq("Study group")
        expect(group.members).to eq([ friend ])
        expect(flash[:alert]).to include("Nothing was saved")
      end

      it "reports a name that is too long" do
        group = create(:friend_group, user: user, name: "Study group")

        patch dashboard_friend_group_path(group.public_id), params: { name: "x" * 51 }

        expect(group.reload.name).to eq("Study group")
        expect(flash[:alert]).to eq("Name is too long (maximum is 50 characters)")
      end

      it "does not rename another user's group" do
        group = create(:friend_group, name: "Theirs")

        patch dashboard_friend_group_path(group.public_id), params: { name: "Mine" }

        expect(group.reload.name).to eq("Theirs")
        expect(flash[:alert]).to eq("Group not found.")
      end

      it "changes the end date" do
        group = create(:friend_group, :temporary, user: user)

        patch dashboard_friend_group_path(group.public_id), params: { name: group.name, expires_on: "2099-06-30" }

        expect(group.reload.expires_at).to eq(Time.zone.parse("2099-06-30 23:59:59 -04:00"))
      end

      it "removes the end date when the field is empty" do
        group = create(:friend_group, :temporary, user: user)

        patch dashboard_friend_group_path(group.public_id), params: { name: group.name, expires_on: "" }

        expect(group.reload.expires_at).to be_nil
      end
    end

    describe "DELETE /dashboard/friends/groups/:id" do
      it "deletes the group" do
        group = create(:friend_group, user: user, name: "Study group")
        add_to(group)

        delete dashboard_friend_group_path(group.public_id)

        expect(FriendGroup.exists?(group.id)).to be(false)
        expect(user.friend_of?(friend)).to be(true)
        expect(flash[:notice]).to eq("Group \"Study group\" deleted.")
      end

      it "does not delete another user's group" do
        group = create(:friend_group)

        delete dashboard_friend_group_path(group.public_id)

        expect(FriendGroup.exists?(group.id)).to be(true)
      end
    end

    describe "POST /dashboard/friends/groups/:friend_group_id/members" do
      let(:group) { create(:friend_group, user: user, name: "Study group") }

      it "adds a friend" do
        post dashboard_friend_group_members_path(group.public_id), params: { friend_id: friend.public_id }

        expect(group.reload.members).to eq([ friend ])
        expect(flash[:notice]).to eq("Added to \"Study group\".")
      end

      it "refuses a user who is not a friend" do
        post dashboard_friend_group_members_path(group.public_id), params: { friend_id: create(:user).public_id }

        expect(group.memberships).to be_empty
        expect(flash[:alert]).to eq("Friend not found.")
      end
    end

    describe "DELETE /dashboard/friends/groups/:friend_group_id/members/:id" do
      let(:group) { create(:friend_group, user: user, name: "Study group") }

      it "removes a friend from the group" do
        add_to(group)

        delete dashboard_friend_group_member_path(group.public_id, friend.public_id)

        expect(group.memberships).to be_empty
        expect(flash[:notice]).to eq("Removed from \"Study group\".")
      end

      it "reports a friend who is not in the group" do
        delete dashboard_friend_group_member_path(group.public_id, friend.public_id)

        expect(flash[:alert]).to eq("Friend not found in this group.")
      end
    end

    it "removes the friend from every group when the friend is removed" do
      group = create(:friend_group, user: user)
      add_to(group)

      delete dashboard_friend_path(friend.public_id)

      expect(group.memberships).to be_empty
      expect(FriendGroup.exists?(group.id)).to be(true)
    end
  end
end
