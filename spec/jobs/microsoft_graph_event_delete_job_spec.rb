# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraphEventDeleteJob, :microsoft_graph do
  let(:credential) { create(:oauth_credential, :microsoft, token_expires_at: 1.hour.from_now) }

  it "deletes the remote event with the owner's credential" do
    delete = stub_request(:delete, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/events/AAMkSyntheticEvent1")
             .with(headers: { "Authorization" => "Bearer #{credential.access_token}" })
             .to_return(status: 204)

    described_class.perform_now(credential.id, "AAMkSyntheticEvent1", "synthetic-uid")

    expect(delete).to have_been_requested
  end

  it "does nothing once the credential is gone" do
    expect { described_class.perform_now(0, "AAMkSyntheticEvent1") }.not_to raise_error
  end

  it "does nothing for a Google credential" do
    google = create(:oauth_credential)

    expect { described_class.perform_now(google.id, "AAMkSyntheticEvent1") }.not_to raise_error
  end
end
