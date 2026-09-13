# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: friendships
#
#  id           :bigint           not null, primary key
#  status       :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  addressee_id :bigint           not null
#  requester_id :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id                   (addressee_id)
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_requester_id                   (requester_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
RSpec.describe Friendship, type: :model do
  include ActiveJob::TestHelper

  let(:requester) do
    User.create!(email: "requester@wit.edu", password: "password123",
                 first_name: "Ada", last_name: "Lovelace")
  end
  let(:addressee) do
    User.create!(email: "addressee@wit.edu", password: "password123",
                 first_name: "Grace", last_name: "Hopper")
  end

  describe "the friend request email" do
    it "emails the requestee when a pending request is created" do
      expect {
        Friendship.create!(requester: requester, addressee: addressee)
      }.to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "does not email when an admin creates an already accepted friendship" do
      expect {
        Friendship.create!(requester: requester, addressee: addressee, status: :accepted)
      }.not_to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "does not email when the request is accepted later" do
      friendship = Friendship.create!(requester: requester, addressee: addressee)

      expect { friendship.accepted! }.not_to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "does not email when the request is invalid" do
      Friendship.create!(requester: requester, addressee: addressee)

      expect {
        Friendship.create(requester: addressee, addressee: requester)
      }.not_to have_enqueued_mail(FriendshipMailer, :request_received)
    end
  end
end
