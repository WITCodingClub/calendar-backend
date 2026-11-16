# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passkeys::Authentication do
  def reason_of
    yield
    nil
  rescue described_class::Failed => e
    e.reason
  end

  describe ".options" do
    it "issues an authentication challenge with no allow list" do
      result = described_class.options
      options = result[:options].with_indifferent_access

      challenge = WebauthnChallenge.consume(handle: result[:handle], purpose: "authentication")
      expect(challenge.challenge).to eq(options[:challenge])
      expect(options[:allowCredentials]).to be_blank
    end
  end

  describe ".verify!" do
    it "fails as expired for a handle with no challenge" do
      expect(reason_of { described_class.verify!(handle: "missing", credential: {}) }).to eq(:expired)
    end

    it "fails as rejected for a credential the gem cannot read" do
      handle = described_class.options[:handle]
      credential = { "type" => "public-key", "id" => "!!", "rawId" => "!!",
                     "response" => { "clientDataJSON" => "!!", "authenticatorData" => "!!", "signature" => "!!" } }

      expect(reason_of { described_class.verify!(handle: handle, credential: credential) }).to eq(:rejected)
    end
  end
end
