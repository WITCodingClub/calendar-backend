# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passkeys::Registration do
  let(:user) { create(:user) }

  def failure_of
    yield
    nil
  rescue Passkeys::Failed => e
    [ e.reason, e.message ]
  end

  describe ".options" do
    it "issues a registration challenge for the user that excludes the user's passkeys" do
      existing = create(:passkey, user: user)

      result  = described_class.options(user)
      options = result[:options].with_indifferent_access

      challenge = WebauthnChallenge.consume(handle: result[:handle], purpose: "registration")
      expect(challenge.user_id).to eq(user.id)
      expect(options[:excludeCredentials].pluck(:id)).to eq([ existing.external_id ])
    end
  end

  describe ".create!" do
    it "fails as expired for a challenge of another account" do
      handle = described_class.options(create(:user))[:handle]

      expect(failure_of { described_class.create!(user: user, handle: handle, params: ActionController::Parameters.new) })
        .to eq([ :expired, "Passkey registration expired. Start again." ])
    end

    it "fails as rejected for a credential the gem cannot read" do
      handle = described_class.options(user)[:handle]
      credential = { "type" => "public-key", "id" => "!!", "rawId" => "!!",
                     "response" => { "clientDataJSON" => "!!", "attestationObject" => "!!" } }

      expect(failure_of { described_class.create!(user: user, handle: handle, params: ActionController::Parameters.new(credential: credential)) })
        .to eq([ :rejected, "Could not verify this passkey" ])
    end
  end

  describe ".default_nickname" do
    it "numbers the next free name" do
      expect(described_class.default_nickname(user)).to eq("Passkey")

      create(:passkey, user: user, nickname: "Passkey")
      create(:passkey, user: user, nickname: "Passkey 2")
      expect(described_class.default_nickname(user)).to eq("Passkey 3")
    end
  end
end
