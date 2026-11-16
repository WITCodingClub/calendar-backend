# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::Providers do
  let(:user) { create(:user) }

  after { Flipper.disable(FeatureFlags::MICROSOFT_GRAPH_CALENDAR) }

  def enable_microsoft_for(person)
    Flipper.enable_actor(FeatureFlags::MICROSOFT_GRAPH_CALENDAR, person)
  end

  describe ".services_for" do
    it "uses Google alone for a Google user, as before" do
      create(:oauth_credential, user: user)

      expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendar::Provider ])
    end

    it "syncs nothing for a person with no Google credential and no Microsoft calendar" do
      expect(described_class.services_for(user)).to be_empty
    end

    it "ignores a Microsoft calendar while the provider is not configured" do
      create(:oauth_credential, user: user)
      create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))
      enable_microsoft_for(user)

      expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendar::Provider ])
    end

    context "when the provider is configured", :microsoft_graph do
      it "adds Microsoft for a person with the flag and a Microsoft calendar" do
        create(:oauth_credential, user: user)
        create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))
        enable_microsoft_for(user)

        expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendar::Provider, MicrosoftGraph::CalendarProvider ])
      end

      it "uses Microsoft alone for a person without Google" do
        create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))
        enable_microsoft_for(user)

        expect(described_class.services_for(user).map(&:class)).to eq([ MicrosoftGraph::CalendarProvider ])
      end

      it "syncs nothing for a Microsoft-only person once the flag is off" do
        create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))

        expect(described_class.services_for(user)).to be_empty
      end
    end
  end

  describe ".for" do
    it "gives the provider class of each stored name" do
      expect(described_class.for("google")).to eq(GoogleCalendar::Provider)
      expect(described_class.for(:microsoft)).to eq(MicrosoftGraph::CalendarProvider)
    end

    it "raises for a name it does not know" do
      expect { described_class.for("yahoo") }.to raise_error(KeyError)
    end
  end

  describe ".syncs?" do
    let(:user) { create(:user) }

    it "is true for a person with a Google credential" do
      create(:oauth_credential, user: user)

      expect(described_class.syncs?(user)).to be(true)
    end

    it "is false for a person whose Microsoft calendar the flag keeps out" do
      create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))

      expect(described_class.syncs?(user)).to be(false)
    end
  end

  describe ".invalid_grant?" do
    it "is true for a Google refusal of the grant" do
      expect(described_class.invalid_grant?(Signet::AuthorizationError.new('{"error": "invalid_grant"}'))).to be(true)
    end

    it "is true for a Microsoft refusal of the grant" do
      error = MicrosoftGraph::AuthError.new("token request failed", status: 400, body: { "error" => "invalid_grant" })

      expect(described_class.invalid_grant?(error)).to be(true)
    end

    it "is false for another token error or any other error" do
      expect(described_class.invalid_grant?(Signet::AuthorizationError.new('{"error": "invalid_client"}'))).to be(false)
      expect(described_class.invalid_grant?(MicrosoftGraph::AuthError.new("no refresh token"))).to be(false)
      expect(described_class.invalid_grant?(StandardError.new("invalid_grant"))).to be(false)
    end
  end

  describe "the error lists" do
    it "joins the errors of every provider" do
      expect(described_class.auth_errors).to include(Google::Apis::AuthorizationError, Signet::AuthorizationError, MicrosoftGraph::AuthError)
      expect(described_class.rate_limit_errors).to eq([ Google::Apis::RateLimitError ])
      expect(described_class.transient_errors).to include(Google::Apis::ServerError, MicrosoftGraph::Error)
    end
  end

  describe "the connect paths" do
    it "starts the Google connection at the OmniAuth path with a state for the user" do
      path  = GoogleCalendar::Provider.connect_path(user, email: "linked@example.com")
      state = Rack::Utils.parse_query(URI(path).query)["state"]

      expect(path).to start_with("/auth/google_oauth2?state=")
      expect(GoogleSignIn::OauthState.verify(state)).to include("user_id" => user.id, "email" => "linked@example.com")
    end

    it "starts the Microsoft connection at its route with the placement in the state" do
      path  = MicrosoftGraph::CalendarProvider.connect_path(user, placement: "primary")
      state = Rack::Utils.parse_query(URI(path).query)["state"]

      expect(path).to start_with("/auth/microsoft_graph?state=")
      expect(MicrosoftGraph::OauthState.verify(state)).to include("user_id" => user.id, "placement" => "primary")
    end
  end
end
