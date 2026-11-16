# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passkeys::Authentication do
  def reason_of
    yield
    nil
  rescue Passkeys::Failed => e
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
      params = ActionController::Parameters.new(handle: "missing")

      expect(reason_of { described_class.verify!(handle: "missing", params: params) }).to eq(:expired)
    end

    it "spends the challenge before it reads a missing credential" do
      handle = described_class.options[:handle]

      expect { described_class.verify!(handle: handle, params: ActionController::Parameters.new) }
        .to raise_error(ActionController::ParameterMissing)
      expect(WebauthnChallenge.consume(handle: handle, purpose: "authentication")).to be_nil
    end

    it "fails as rejected for a credential the gem cannot read" do
      handle = described_class.options[:handle]
      credential = { "type" => "public-key", "id" => "!!", "rawId" => "!!",
                     "response" => { "clientDataJSON" => "!!", "authenticatorData" => "!!", "signature" => "!!" } }

      params = ActionController::Parameters.new(credential: credential)

      expect(reason_of { described_class.verify!(handle: handle, params: params) }).to eq(:rejected)
    end
  end
end
