# frozen_string_literal: true

# == Schema Information
#
# Table name: emails
# Database name: primary
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  g_cal      :boolean          default(FALSE), not null
#  primary    :boolean          default(FALSE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_emails_on_email                (email) UNIQUE
#  index_emails_on_user_id              (user_id)
#  index_emails_on_user_id_and_primary  (user_id,primary) UNIQUE WHERE ("primary" = true)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe Email do
  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with valid attributes" do
      email = build(:email, user: user, email: "test@example.com")
      expect(email).to be_valid
    end

    it "requires email to be present" do
      email = build(:email, user: user, email: nil)
      expect(email).not_to be_valid
      expect(email.errors[:email]).to include("can't be blank")
    end

    it "requires email to be unique" do
      create(:email, user: user, email: "test@example.com")
      duplicate = build(:email, user: create(:user), email: "test@example.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("has already been taken")
    end

    it "requires email to have valid format" do
      # The regex /\A[^@\s]+@[^@\s]+\z/ is permissive - just requires something@something with no spaces
      invalid_emails = ["invalid", "@nodomain.com", "spaces in@email.com", "no@spaces allowed.com"]
      invalid_emails.each do |invalid_email|
        email = build(:email, user: user, email: invalid_email)
        expect(email).not_to be_valid
        expect(email.errors[:email]).to include("must be a valid email address")
      end
    end

    it "accepts valid email formats" do
      valid_emails = ["test@example.com", "user.name@domain.org", "user+tag@domain.co"]
      valid_emails.each do |valid_email|
        email = build(:email, user: user, email: valid_email)
        expect(email).to be_valid
      end
    end
  end

  describe "primary email validation" do
    it "allows one primary email per user" do
      primary_email = create(:email, user: user, email: "primary@example.com", primary: true)
      expect(primary_email).to be_valid
    end

    it "prevents multiple primary emails for same user" do
      create(:email, user: user, email: "primary@example.com", primary: true)
      second_primary = build(:email, user: user, email: "second@example.com", primary: true)
      expect(second_primary).not_to be_valid
      expect(second_primary.errors[:primary]).to include("There can only be one primary email.")
    end

    it "allows different users to each have a primary email" do
      other_user = create(:user)
      create(:email, user: user, email: "user1@example.com", primary: true)
      other_primary = build(:email, user: other_user, email: "user2@example.com", primary: true)
      expect(other_primary).to be_valid
    end

    it "allows multiple non-primary emails for same user" do
      create(:email, user: user, email: "email1@example.com", primary: false)
      second_email = build(:email, user: user, email: "email2@example.com", primary: false)
      expect(second_email).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a user" do
      email = create(:email, user: user)
      expect(email.user).to eq(user)
    end
  end

  describe "#is_wit_email?" do
    it "returns true for @wit.edu emails" do
      email = build(:email, user: user, email: "student@wit.edu")
      expect(email.is_wit_email?).to be true
    end

    it "returns true for @wit.edu emails regardless of case" do
      email = build(:email, user: user, email: "student@WIT.EDU")
      expect(email.is_wit_email?).to be true
    end

    it "returns false for non-wit.edu emails" do
      email = build(:email, user: user, email: "user@gmail.com")
      expect(email.is_wit_email?).to be false
    end

    it "returns false for emails containing wit.edu but not at end" do
      email = build(:email, user: user, email: "user@wit.edu.fake.com")
      expect(email.is_wit_email?).to be false
    end
  end

  describe "public_id" do
    it "generates a public_id with eml prefix" do
      email = create(:email, user: user, email: "test@example.com")
      expect(email.public_id).to start_with("eml_")
    end
  end
end
