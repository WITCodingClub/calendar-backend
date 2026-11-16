# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredentials::AccountLink do
  let(:user)   { create(:user) }
  let(:tokens) { { uid: "synthetic-uid", email: "linked@example.com", access_token: "synthetic-access", refresh_token: "synthetic-refresh" } }

  describe "#link!" do
    it "saves the tokens of a provider account on the user" do
      credential = described_class.new(user, "microsoft").link!(**tokens, expires_at: 1.hour.from_now)

      expect(credential).to have_attributes(provider: "microsoft", uid: "synthetic-uid", email: "linked@example.com",
                                            refresh_token: "synthetic-refresh")
      expect(credential.token_expires_at).to be > 50.minutes.from_now
    end

    it "takes the expiry as epoch seconds too, as OmniAuth gives it" do
      credential = described_class.new(user, "google").link!(**tokens, expires_at: 1.hour.from_now.to_i)

      expect(credential.token_expires_at).to be > 50.minutes.from_now
    end

    it "keeps the refresh token when the provider sends none" do
      described_class.new(user, "google").link!(**tokens)

      credential = described_class.new(user, "google").link!(**tokens, refresh_token: nil, access_token: "synthetic-new")

      expect(credential.reload).to have_attributes(access_token: "synthetic-new", refresh_token: "synthetic-refresh")
    end

    it "clears the revoked flag, so a new sign-in replaces a refused grant" do
      described_class.new(user, "microsoft").link!(**tokens).mark_revoked!("invalid_grant")

      credential = described_class.new(user, "microsoft").link!(**tokens, access_token: "synthetic-new")

      expect(credential.reload).not_to be_token_revoked
    end

    it "refuses an account that another user connected, and names the provider" do
      create(:oauth_credential, :microsoft, uid: "synthetic-uid")

      expect { described_class.new(user, "microsoft").link!(**tokens) }
        .to raise_error(described_class::Conflict, "That Microsoft account is already connected to another user")
    end
  end

  describe "#connect!" do
    it "links the account, then makes the calendar and syncs through the provider" do
      service = instance_double(MicrosoftGraph::CalendarProvider, ensure_course_calendar: "synthetic-calendar")
      allow(MicrosoftGraph::CalendarProvider).to receive(:new).and_return(service)

      calendar_id = described_class.new(user, "microsoft").connect!(**tokens, calendar: { placement: "primary" })

      expect(calendar_id).to eq("synthetic-calendar")
      expect(MicrosoftGraph::CalendarProvider).to have_received(:new).with(user, credential: user.oauth_credentials.microsoft.sole)
      expect(service).to have_received(:ensure_course_calendar).with(always_sync: true, placement: "primary")
    end
  end
end
