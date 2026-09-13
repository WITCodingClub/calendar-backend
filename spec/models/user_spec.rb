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
  def create_user(email)
    User.create!(email: email, password: "password123")
  end

  describe "#remove_friend" do
    let(:user)   { create_user("me@wit.edu") }
    let(:friend) { create_user("friend@wit.edu") }

    it "deletes the friendship when this user sent the request" do
      Friendship.create!(requester: user, addressee: friend, status: :accepted)

      expect(user.remove_friend(friend)).to be(true)
      expect(user.friends).to be_empty
      expect(friend.friends).to be_empty
    end

    it "deletes the friendship when the other user sent the request" do
      Friendship.create!(requester: friend, addressee: user, status: :accepted)

      expect(user.remove_friend(friend)).to be(true)
      expect(user.friends).to be_empty
    end

    it "leaves a pending request alone" do
      friendship = Friendship.create!(requester: user, addressee: friend)

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
end
