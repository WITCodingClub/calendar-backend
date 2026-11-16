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
end
