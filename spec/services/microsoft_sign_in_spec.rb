# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftSignIn do
  after { Flipper.disable(FlipperFlags::MICROSOFT_SIGN_IN) }

  describe ".configured?" do
    it "is true with a client id, a secret and a tenant id" do
      configure_microsoft_sign_in

      expect(described_class).to be_configured
    end

    it "is false without a client secret" do
      configure_microsoft_sign_in(client_secret: nil)

      expect(described_class).not_to be_configured
    end

    it "is false without a client id" do
      configure_microsoft_sign_in(client_id: nil)

      expect(described_class).not_to be_configured
    end

    # The strategy checks the ID token issuer against the tenant, so the
    # multi-tenant "organizations" value cannot sign anyone in.
    it "is false when the tenant is organizations" do
      configure_microsoft_sign_in(tenant_id: nil)

      expect(described_class.config[:tenant_id]).to eq("organizations")
      expect(described_class).not_to be_configured
    end
  end

  describe ".enabled?" do
    before { configure_microsoft_sign_in }

    it "is false while the flag is off" do
      expect(described_class).not_to be_enabled
    end

    it "is true when the flag is fully on" do
      Flipper.enable(FlipperFlags::MICROSOFT_SIGN_IN)

      expect(described_class).to be_enabled
    end

    # Nobody is signed in before a sign-in, so the check has no actor.
    it "is false when the flag is on only for one user" do
      Flipper.enable_actor(FlipperFlags::MICROSOFT_SIGN_IN, create(:user))

      expect(described_class).not_to be_enabled
    end

    it "is false when the client is not configured, even with the flag on" do
      configure_microsoft_sign_in(client_id: nil)
      Flipper.enable(FlipperFlags::MICROSOFT_SIGN_IN)

      expect(described_class).not_to be_enabled
    end
  end

  describe ".request_phase?" do
    before do
      configure_microsoft_sign_in
      Flipper.enable(FlipperFlags::MICROSOFT_SIGN_IN)
    end

    it "is true for a POST to the request path" do
      expect(described_class.request_phase?("PATH_INFO" => "/auth/microsoft", "REQUEST_METHOD" => "POST")).to be(true)
    end

    it "is false for a GET" do
      expect(described_class.request_phase?("PATH_INFO" => "/auth/microsoft", "REQUEST_METHOD" => "GET")).to be(false)
    end

    it "is false for another path" do
      expect(described_class.request_phase?("PATH_INFO" => "/auth/microsoft_graph", "REQUEST_METHOD" => "POST")).to be(false)
    end
  end
end
