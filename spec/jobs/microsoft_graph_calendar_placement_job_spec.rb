# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraphCalendarPlacementJob, :microsoft_graph do
  include ActiveJob::TestHelper

  let(:user)       { create(:user) }
  let(:credential) { create(:oauth_credential, :microsoft, user: user, token_expires_at: 1.hour.from_now) }

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  context "when the provider is on for the person" do
    before { Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user) }

    # A job spec that only calls a service may stub the service class.
    it "changes the placement and then starts a forced sync" do
      credential
      service = instance_double(MicrosoftGraphCalendarService, credential: credential, change_placement: "AAMkSyntheticPrimaryCalendar")
      allow(MicrosoftGraphCalendarService).to receive(:new).with(user).and_return(service)

      expect { described_class.perform_now(user, "primary") }
        .to have_enqueued_job(GoogleCalendarSyncJob).with(user, force: true)

      expect(service).to have_received(:change_placement).with("primary")
    end

    it "does nothing for a person with no Microsoft account" do
      expect { described_class.perform_now(user, "primary") }.not_to have_enqueued_job(GoogleCalendarSyncJob)
    end
  end

  it "does nothing while the provider is off" do
    credential
    allow(MicrosoftGraphCalendarService).to receive(:new)

    described_class.perform_now(user, "primary")

    expect(MicrosoftGraphCalendarService).not_to have_received(:new)
  end

  it "shares the sync job's concurrency key, so a move and a sync never overlap" do
    move = described_class.new(user, "primary")
    sync = GoogleCalendarSyncJob.new(user, force: true)

    expect(move.concurrency_key).to eq(sync.concurrency_key)
  end
end
