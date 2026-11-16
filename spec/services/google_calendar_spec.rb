# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar do
  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:google, :client_id).and_return("web-client")
  end

  describe ".client_ids" do
    it "accepts the web client and each listed client, once each" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_IDS").and_return(" extension-client , web-client,")

      expect(described_class.client_ids).to eq(%w[extension-client web-client])
    end
  end

  describe ".configure_strategy" do
    it "sets the client and the scopes on the OmniAuth strategy" do
      strategy = Struct.new(:options).new(OmniAuth::Strategy::Options.new)

      described_class.configure_strategy(strategy)

      expect(strategy.options.client_id).to eq("web-client")
      expect(strategy.options.scope.split).to include("email", described_class::CALENDAR_SCOPE)
    end
  end
end
