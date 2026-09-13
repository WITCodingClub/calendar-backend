# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: webauthn_challenges
#
#  id         :bigint           not null, primary key
#  challenge  :string           not null
#  expires_at :datetime         not null
#  handle     :string           not null
#  purpose    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint
#
# Indexes
#
#  index_webauthn_challenges_on_expires_at  (expires_at)
#  index_webauthn_challenges_on_handle      (handle) UNIQUE
#  index_webauthn_challenges_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe WebauthnChallenge do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "challenge@wit.edu", password: "password123") }

  it "hands back the challenge it was issued with" do
    record = described_class.issue!(challenge: "abc123", purpose: "authentication")

    expect(described_class.consume(handle: record.handle, purpose: "authentication").challenge).to eq("abc123")
  end

  it "can be spent only once" do
    record = described_class.issue!(challenge: "abc123", purpose: "authentication")

    described_class.consume(handle: record.handle, purpose: "authentication")

    expect(described_class.consume(handle: record.handle, purpose: "authentication")).to be_nil
  end

  it "refuses a handle issued for the other ceremony" do
    record = described_class.issue!(challenge: "abc123", purpose: "registration", user: user)

    expect(described_class.consume(handle: record.handle, purpose: "authentication")).to be_nil
  end

  it "refuses a handle that sat past its life" do
    record = described_class.issue!(challenge: "abc123", purpose: "authentication")

    travel(described_class::TTL + 1.minute) do
      expect(described_class.consume(handle: record.handle, purpose: "authentication")).to be_nil
    end
  end

  it "refuses a handle that was never issued" do
    expect(described_class.consume(handle: "made-up", purpose: "authentication")).to be_nil
    expect(described_class.consume(handle: nil, purpose: "authentication")).to be_nil
  end

  it "clears out rows that expired, so the table does not grow without bound" do
    stale = described_class.issue!(challenge: "old", purpose: "authentication")

    travel(described_class::TTL + 1.minute) do
      described_class.issue!(challenge: "new", purpose: "authentication")
    end

    expect(described_class.exists?(stale.id)).to be(false)
  end
end
