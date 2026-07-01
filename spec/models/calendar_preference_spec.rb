# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarPreference, type: :model do
  def create_user(email)
    User.create!(email: email, password: "password123", first_name: "Test", last_name: "User")
  end

  let(:user) { create_user("pref@wit.edu") }

  it "allows a single global preference for a user" do
    expect(described_class.new(user: user, scope: :global)).to be_valid
  end

  it "rejects a second global preference for the same user" do
    described_class.create!(user: user, scope: :global)

    dupe = described_class.new(user: user, scope: :global)

    expect(dupe).not_to be_valid
    expect(dupe.errors[:base].join).to match(/global preference already exists/)
  end

  it "does not flag the existing record as a duplicate of itself" do
    pref = described_class.create!(user: user, scope: :global)

    expect(pref).to be_valid
  end

  it "allows a global preference for a different user" do
    described_class.create!(user: user, scope: :global)
    other = create_user("pref2@wit.edu")

    expect(described_class.new(user: other, scope: :global)).to be_valid
  end
end
