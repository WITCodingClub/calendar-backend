# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: friendships
#
#  id                   :bigint           not null, primary key
#  addressee_visibility :integer          default(0), not null
#  expires_at           :datetime
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
#  index_friendships_on_expires_at                     (expires_at) WHERE (expires_at IS NOT NULL)
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
  include ActiveSupport::Testing::TimeHelpers

  describe "associations and validations" do
    subject { create(:friendship) }

    it { is_expected.to belong_to(:requester).class_name("User") }
    it { is_expected.to belong_to(:addressee).class_name("User") }
    it { is_expected.to have_many(:friend_group_memberships).dependent(:delete_all) }

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

  describe "#friend_id_for" do
    it "returns the other user's id from either side" do
      friendship = create(:friendship, requester: requester, addressee: addressee)

      expect(friendship.friend_id_for(requester)).to eq(addressee.id)
      expect(friendship.friend_id_for(addressee)).to eq(requester.id)
    end
  end

  describe "#involves?" do
    it "is true only for the two users in the friendship" do
      friendship = create(:friendship, requester: requester, addressee: addressee)

      expect(friendship.involves?(requester.id)).to be(true)
      expect(friendship.involves?(addressee.id)).to be(true)
      expect(friendship.involves?(create(:user).id)).to be(false)
    end
  end

  describe "removal" do
    it "removes the friendship's group memberships, also on a delete that skips callbacks" do
      membership = create(:friend_group_membership)

      membership.friendship.delete

      expect(FriendGroupMembership.exists?(membership.id)).to be(false)
    end
  end

  describe "expiry" do
    it "refuses an expiry date in the past" do
      friendship = build(:friendship, requester: requester, addressee: addressee, expires_at: 1.minute.ago)

      expect(friendship).not_to be_valid
      expect(friendship.errors[:expires_at]).to include("must be in the future")
    end

    it "accepts a future expiry date or none" do
      expect(build(:friendship, :temporary)).to be_valid
      expect(build(:friendship, expires_at: nil)).to be_valid
    end

    it "does not check an unchanged date that has passed, so the row can still be updated" do
      friendship = create(:friendship, :temporary, requester: requester, addressee: addressee)

      travel 8.days do
        expect(friendship.update(status: :accepted)).to be(true)
      end
    end

    it "is expired only after the date" do
      friendship = create(:friendship, :temporary)

      expect(friendship).not_to be_expired
      travel 8.days do
        expect(friendship).to be_expired
      end
    end

    it "is never expired without a date" do
      expect(build(:friendship)).not_to be_expired
      expect(build(:friendship)).not_to be_temporary
    end

    describe "scopes" do
      let!(:permanent) { create(:friendship, :accepted) }
      let!(:temporary) { create(:friendship, :accepted, :temporary) }

      it "keeps both friendships before the date" do
        expect(Friendship.active).to contain_exactly(permanent, temporary)
        expect(Friendship.expired).to be_empty
      end

      it "drops a friendship from active and accepted_for after the date" do
        travel 8.days do
          expect(Friendship.active).to contain_exactly(permanent)
          expect(Friendship.accepted_for(temporary.requester)).to be_empty
          expect(Friendship.expired).to contain_exactly(temporary)
        end
      end

      it "drops an expired request from the incoming and outgoing lists" do
        request = create(:friendship, :temporary, requester: requester, addressee: addressee)

        travel 8.days do
          expect(Friendship.pending_for(addressee)).not_to include(request)
          expect(Friendship.outgoing_from(requester)).not_to include(request)
        end
      end
    end

    it "removes an expired friendship between the same two people before a new request" do
      old = create(:friendship, :accepted, :temporary, requester: requester, addressee: addressee)

      travel 8.days do
        new_request = Friendship.create(requester: addressee, addressee: requester)

        expect(new_request).to be_persisted
        expect(Friendship.exists?(old.id)).to be(false)
      end
    end

    it "keeps an unexpired friendship and refuses the new request" do
      create(:friendship, :accepted, :temporary, requester: requester, addressee: addressee)

      expect(Friendship.create(requester: addressee, addressee: requester)).not_to be_persisted
    end
  end
end
