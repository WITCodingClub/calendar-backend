# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: friendships
#
#  id                   :bigint           not null, primary key
#  addressee_visibility :integer          default(0), not null
#  requester_visibility :integer          default(0), not null
#  status               :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  addressee_id         :bigint           not null
#  requester_id         :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#  index_friendships_on_unordered_pair                 (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
RSpec.describe Friendship, type: :model do
  include ActiveJob::TestHelper

  describe "associations and validations" do
    subject { create(:friendship) }

    it { is_expected.to belong_to(:requester).class_name("User") }
    it { is_expected.to belong_to(:addressee).class_name("User") }

    it { is_expected.to validate_uniqueness_of(:requester_id).scoped_to(:addressee_id).with_message("friendship already exists") }

    it { is_expected.to define_enum_for(:status).with_values(pending: 0, accepted: 1).backed_by_column_of_type(:integer).with_default(:pending) }
    it { is_expected.to define_enum_for(:requester_visibility).with_values(full: 0, availability_only: 1).backed_by_column_of_type(:integer).with_prefix(:requester).with_default(:full) }
    it { is_expected.to define_enum_for(:addressee_visibility).with_values(full: 0, availability_only: 1).backed_by_column_of_type(:integer).with_prefix(:addressee).with_default(:full) }

    # #cannot_friend_self and #no_reverse_friendship_exists are custom,
    # cross-record validations with no single attribute to point a one-liner
    # at.
  end

  let(:requester) { create(:user) }
  let(:addressee) { create(:user) }

  describe "the friend request email" do
    it "emails the requestee when a pending request is created" do
      expect {
        create(:friendship, requester: requester, addressee: addressee)
      }.to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "does not email when an admin creates an already accepted friendship" do
      expect {
        create(:friendship, :accepted, requester: requester, addressee: addressee)
      }.not_to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "does not email when the request is accepted later" do
      friendship = create(:friendship, requester: requester, addressee: addressee)

      expect { friendship.accepted! }.not_to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "does not email when the request is invalid" do
      create(:friendship, requester: requester, addressee: addressee)

      expect {
        Friendship.create(requester: addressee, addressee: requester)
      }.not_to have_enqueued_mail(FriendshipMailer, :request_received)
    end
  end

  describe "visibility" do
    let(:friendship) { create(:friendship, :accepted, requester: requester, addressee: addressee) }

    it "shares the full schedule both ways by default" do
      expect(friendship.visibility_set_by(requester)).to eq("full")
      expect(friendship.visibility_set_by(addressee)).to eq("full")
      expect(friendship.full_schedule_visible_to?(requester)).to be(true)
      expect(friendship.full_schedule_visible_to?(addressee)).to be(true)
    end

    it "lets each side set the level for its own schedule only" do
      friendship.update_visibility_for!(addressee, :availability_only)

      expect(friendship.reload).to be_addressee_availability_only
      expect(friendship).to be_requester_full
      # The addressee hid their courses from the requester, not the reverse.
      expect(friendship.full_schedule_visible_to?(requester)).to be(false)
      expect(friendship.full_schedule_visible_to?(addressee)).to be(true)
    end

    it "sets the requester's own column for the requester" do
      friendship.update_visibility_for!(requester, "availability_only")

      expect(friendship.reload.visibility_set_by(requester)).to eq("availability_only")
      expect(friendship.visibility_set_by(addressee)).to eq("full")
    end

    it "refuses an unknown level" do
      expect { friendship.update_visibility_for!(requester, "hidden") }.to raise_error(ArgumentError)
      expect(friendship.reload).to be_requester_full
    end
  end

  describe ".between" do
    it "finds the friendship in either direction" do
      friendship = create(:friendship, requester: requester, addressee: addressee)
      create(:friendship, requester: requester, addressee: create(:user))

      expect(described_class.between(requester, addressee)).to contain_exactly(friendship)
      expect(described_class.between(addressee, requester)).to contain_exactly(friendship)
    end
  end

  describe "removing a friend" do
    it "takes the ex-friends off each other's future meetings" do
      friendship = create(:friendship, :accepted)
      allow(FriendMeetingAttendeeRemover).to receive(:call)

      friendship.destroy!

      expect(FriendMeetingAttendeeRemover).to have_received(:call).with(friendship.requester_id, friendship.addressee_id)
    end

    it "does nothing when a pending request is cancelled" do
      friendship = create(:friendship)
      allow(FriendMeetingAttendeeRemover).to receive(:call)

      friendship.destroy!

      expect(FriendMeetingAttendeeRemover).not_to have_received(:call)
    end
  end
end
