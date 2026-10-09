# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default(0), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  confirmation_sent_at         :datetime
#  confirmation_token           :string
#  confirmed_at                 :datetime
#  current_sign_in_at           :datetime
#  current_sign_in_ip           :string
#  email                        :string           default(""), not null
#  encrypted_password           :string           default(""), not null
#  failed_attempts              :integer          default(0), not null
#  first_name                   :string
#  friend_emails                :boolean          default(TRUE), not null
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  last_sign_in_at              :datetime
#  last_sign_in_ip              :string
#  locked_at                    :datetime
#  notifications_disabled_until :datetime
#  remember_created_at          :datetime
#  reset_password_sent_at       :datetime
#  reset_password_token         :string
#  sign_in_count                :integer          default(0), not null
#  unconfirmed_email            :string
#  unlock_token                 :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_access_level           (access_level)
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_confirmation_token     (confirmation_token) UNIQUE
#  index_users_on_email                  (email) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#  index_users_on_reset_password_token   (reset_password_token) UNIQUE
#
require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations and validations" do
    subject { create(:user) }

    it { is_expected.to have_many(:enrollments).dependent(:destroy) }
    it { is_expected.to have_many(:courses).through(:enrollments) }
    it { is_expected.to have_many(:term_processing_statuses).dependent(:delete_all) }
    it { is_expected.to have_many(:oauth_credentials).dependent(:destroy) }
    it { is_expected.to have_many(:course_calendars).through(:oauth_credentials) }
    it { is_expected.to have_many(:calendar_events).through(:course_calendars) }
    it { is_expected.to have_many(:calendar_preferences).dependent(:destroy) }
    it { is_expected.to have_many(:event_preferences).dependent(:destroy) }
    it { is_expected.to have_one(:user_extension_config).dependent(:destroy) }
    it { is_expected.to have_many(:security_events).dependent(:destroy) }
    it { is_expected.to have_many(:passkeys).dependent(:destroy) }
    it { is_expected.to have_many(:sign_in_identities).dependent(:destroy) }
    it { is_expected.to have_many(:user_sessions).dependent(:destroy) }
    it { is_expected.to have_many(:sent_friendships).class_name("Friendship").with_foreign_key(:requester_id).dependent(:destroy) }
    it { is_expected.to have_many(:received_friendships).class_name("Friendship").with_foreign_key(:addressee_id).dependent(:destroy) }
    it { is_expected.to have_many(:friend_groups).dependent(:destroy) }
    it { is_expected.to have_many(:friend_meetings).dependent(:destroy) }
    it { is_expected.to have_many(:friend_meeting_attendees).dependent(:delete_all) }
    it { is_expected.to have_many(:meeting_links).dependent(:destroy) }
    it { is_expected.to have_many(:guest_meeting_links).class_name("MeetingLink").with_foreign_key(:guest_user_id).dependent(:nullify) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

    it { is_expected.to define_enum_for(:access_level).with_values(user: 0, admin: 1, super_admin: 2, owner: 3).backed_by_column_of_type(:integer).with_default(:user) }
  end

  describe "deleting the account with friend meetings" do
    let(:user)       { create(:user) }
    let(:credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
    let(:calendar)   { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }
    let(:event_url)  { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events/gcal_synthetic_meeting" }

    before { stub_google_service_account }

    it "deletes each meeting event with the token, while the credential still exists, and cancels for the friends" do
      meeting = create(:friend_meeting, :invite_friends, user: user, destinations: %w[google])
      create(:calendar_event, :for_friend_meeting, course_calendar: calendar, friend_meeting: meeting, external_event_id: "gcal_synthetic_meeting")
      credential_at_delete = nil
      delete = stub_request(:delete, event_url).with(query: { "sendUpdates" => "all" },
                                                     headers: { "Authorization" => "Bearer synthetic-user-token" })
                                               .to_return do
        credential_at_delete = OauthCredential.exists?(credential.id)
        { status: 204 }
      end
      stub_request(:any, %r{googleapis\.com/calendar/v3/(?!calendars/synthetic-course-calendar/events)}).to_return(status: 204)

      user.destroy!

      expect(delete).to have_been_requested.once
      expect(credential_at_delete).to be(true)
      expect(FriendMeeting.exists?(meeting.id)).to be(false)
    end

    it "still deletes the account when a provider delete fails" do
      meeting = create(:friend_meeting, user: user, destinations: %w[google])
      create(:calendar_event, :for_friend_meeting, course_calendar: calendar, friend_meeting: meeting, external_event_id: "gcal_synthetic_meeting")
      stub_request(:delete, event_url).with(query: hash_including({}))
                                      .to_return(status: 500, body: "{}", headers: { "Content-Type" => "application/json" })
      stub_request(:any, %r{googleapis\.com/calendar/v3/(?!calendars/synthetic-course-calendar/events)}).to_return(status: 204)

      expect { user.destroy! }.not_to raise_error
      expect(FriendMeeting.exists?(meeting.id)).to be(false)
    end
  end

  describe "#processed_courses?" do
    it "is false before the extension processes any courses" do
      expect(create(:user).processed_courses?).to be(false)
    end

    it "is true when the user has an enrollment in any term" do
      expect(create(:user, :with_processed_courses).processed_courses?).to be(true)
    end
  end

  describe "#super_admin_access?" do
    it "is true for a super admin and an owner only" do
      levels = %i[user admin super_admin owner].index_with { |level| build(:user, access_level: level).super_admin_access? }

      expect(levels).to eq(user: false, admin: false, super_admin: true, owner: true)
    end
  end

  describe "#remove_friend" do
    let(:user)   { create(:user) }
    let(:friend) { create(:user) }

    it "deletes the friendship when this user sent the request" do
      create(:friendship, :accepted, requester: user, addressee: friend)

      expect(user.remove_friend(friend)).to be(true)
      expect(user.friends).to be_empty
      expect(friend.friends).to be_empty
    end

    it "deletes the friendship when the other user sent the request" do
      create(:friendship, :accepted, requester: friend, addressee: user)

      expect(user.remove_friend(friend)).to be(true)
      expect(user.friends).to be_empty
    end

    it "leaves a pending request alone" do
      friendship = create(:friendship, requester: user, addressee: friend)

      expect(user.remove_friend(friend)).to be(false)
      expect(friendship.reload).to be_pending
    end

    it "returns false for a stranger" do
      expect(user.remove_friend(friend)).to be(false)
    end

    it "returns false for nil and for yourself" do
      expect(user.remove_friend(nil)).to be(false)
      expect(user.remove_friend(user)).to be(false)
    end

    it "removes the friend from the user's groups and keeps the groups" do
      friendship = create(:friendship, :accepted, requester: user, addressee: friend)
      group      = create(:friend_group, user: user)
      create(:friend_group_membership, friend_group: group, friendship: friendship)

      expect { user.remove_friend(friend) }.to change(FriendGroupMembership, :count).by(-1)
      expect(group.reload.members).to be_empty
    end
  end

  describe "#friend_of?" do
    let(:user)   { create(:user) }
    let(:friend) { create(:user) }

    it "is true for an accepted friend in either direction" do
      create(:friendship, :accepted, requester: friend, addressee: user)

      expect(user.friend_of?(friend)).to be(true)
      expect(friend.friend_of?(user)).to be(true)
    end

    it "is false for a pending request, a stranger, nil, and yourself" do
      create(:friendship, requester: user, addressee: friend)

      expect(user.friend_of?(friend)).to be(false)
      expect(user.friend_of?(create(:user))).to be(false)
      expect(user.friend_of?(nil)).to be(false)
      expect(user.friend_of?(user)).to be(false)
    end
  end

  describe "#accepted_friendship_with" do
    let(:user)   { create(:user) }
    let(:friend) { create(:user) }

    it "finds the friendship in either direction" do
      friendship = create(:friendship, :accepted, requester: friend, addressee: user)

      expect(user.accepted_friendship_with(friend)).to eq(friendship)
      expect(friend.accepted_friendship_with(user)).to eq(friendship)
    end

    it "ignores a pending request" do
      create(:friendship, requester: user, addressee: friend)

      expect(user.accepted_friendship_with(friend)).to be_nil
    end

    it "returns nil for nil and for yourself" do
      create(:friendship, :accepted, requester: user, addressee: friend)

      expect(user.accepted_friendship_with(nil)).to be_nil
      expect(user.accepted_friendship_with(user)).to be_nil
    end
  end

  describe "expired friendships" do
    include ActiveSupport::Testing::TimeHelpers

    let(:user)   { create(:user) }
    let(:friend) { create(:user) }

    before { create(:friendship, :accepted, :temporary, requester: user, addressee: friend) }

    it "counts the friend before the expiry date" do
      expect(user.friends).to contain_exactly(friend)
      expect(user.friend_of?(friend)).to be(true)
      expect(friend.accepted_friendship_with(user)).to be_present
    end

    it "does not count the friend after the expiry date" do
      travel 8.days do
        expect(user.friends).to be_empty
        expect(friend.friends).to be_empty
        expect(user.friend_of?(friend)).to be(false)
        expect(user.accepted_friendship_with(friend)).to be_nil
        expect(user.remove_friend(friend)).to be(false)
      end
    end
  end

  describe ".wit_email?" do
    it "accepts an address on the WIT domain" do
      expect(described_class.wit_email?("lovelacea@wit.edu")).to be(true)
    end

    it "ignores the case, because Google reports addresses either way" do
      expect(described_class.wit_email?("LovelaceA@WIT.EDU")).to be(true)
    end

    it "rejects a personal address" do
      expect(described_class.wit_email?("ada@gmail.com")).to be(false)
    end

    it "rejects a domain that merely ends with the WIT one" do
      expect(described_class.wit_email?("ada@notwit.edu")).to be(false)
    end

    it "rejects the domain used as a subdomain of somewhere else" do
      expect(described_class.wit_email?("ada@wit.edu.example.com")).to be(false)
    end

    it "rejects a blank address" do
      expect(described_class.wit_email?(nil)).to be(false)
      expect(described_class.wit_email?("")).to be(false)
    end
  end

  describe ".find_or_provision_for_sign_in!" do
    it "finds the account when a provider sends the email in mixed case" do
      user = create(:user, email: "mixed.case@wit.edu")

      found = described_class.find_or_provision_for_sign_in!(email: " Mixed.Case@WIT.edu ", first_name: "Synthetic", last_name: "Person")

      expect(found).to eq(user)
    end

    it "creates a confirmed account for a new address" do
      user = described_class.find_or_provision_for_sign_in!(email: "new.person@wit.edu", first_name: nil, last_name: nil)

      expect(user).to be_persisted.and be_confirmed
      expect(user).to have_attributes(email: "new.person@wit.edu", first_name: "new.person")
    end
  end
end
