# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraphCalendarDeleteJob, :microsoft_graph do
  let(:credential) { create(:oauth_credential, :microsoft, token_expires_at: 1.hour.from_now) }

  it "deletes the calendar from the owner's mailbox" do
    delete = stub_request(:delete, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars/AAMkSyntheticCalendar1").to_return(status: 204)

    described_class.perform_now(credential.id, "AAMkSyntheticCalendar1")

    expect(delete).to have_been_requested
  end

  it "does nothing once the credential is gone" do
    expect { described_class.perform_now(0, "AAMkSyntheticCalendar1") }.not_to raise_error
  end
end
