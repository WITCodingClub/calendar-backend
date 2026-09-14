# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarProviders do
  let(:user) { create(:user) }

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  def enable_microsoft_for(person)
    Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, person)
  end

  describe ".services_for" do
    it "uses Google alone for a Google user, as before" do
      create(:oauth_credential, user: user)

      expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendarService ])
    end

    it "keeps the Google path for a person with no calendar yet" do
      expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendarService ])
    end

    it "ignores a Microsoft calendar while the provider is not configured" do
      create(:oauth_credential, user: user)
      create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))
      enable_microsoft_for(user)

      expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendarService ])
    end

    context "when the provider is configured", :microsoft_graph do
      it "adds Microsoft for a person with the flag and a Microsoft calendar" do
        create(:oauth_credential, user: user)
        create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))
        enable_microsoft_for(user)

        expect(described_class.services_for(user).map(&:class)).to eq([ GoogleCalendarService, MicrosoftGraphCalendarService ])
      end

      it "uses Microsoft alone for a person without Google" do
        create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))
        enable_microsoft_for(user)

        expect(described_class.services_for(user).map(&:class)).to eq([ MicrosoftGraphCalendarService ])
      end

      it "syncs nothing for a Microsoft-only person once the flag is off" do
        create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))

        expect(described_class.services_for(user)).to be_empty
      end
    end
  end

  describe ".merge_stats" do
    it "adds the stats of each provider" do
      stats = described_class.merge_stats([ { created: 1, updated: 2, skipped: 3 }, { created: 4, updated: 0, skipped: 1 } ])

      expect(stats).to eq(created: 5, updated: 2, skipped: 4)
    end

    it "is nil when no provider ran" do
      expect(described_class.merge_stats([])).to be_nil
    end
  end
end
