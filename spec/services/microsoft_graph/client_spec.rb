# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraph::Client, :microsoft_graph do
  subject(:client) { described_class.new(credential) }

  let(:credential) { create(:oauth_credential, :microsoft, access_token: "current-token", token_expires_at: 1.hour.from_now) }
  let(:calendar_url) { "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars/AAMkSyntheticCalendar1" }

  it "sends the bearer token and the Eastern time zone preference" do
    stub = stub_request(:get, calendar_url)
           .with(headers: { "Authorization" => "Bearer current-token", "Prefer" => 'outlook.timezone="Eastern Standard Time"' })
           .to_return(graph_json_response("calendar_found"))

    expect(client.get("me/calendars/AAMkSyntheticCalendar1")).to include("id" => "AAMkSyntheticCalendar1")
    expect(stub).to have_been_requested
  end

  it "returns an empty hash for a 204 response" do
    stub_request(:delete, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/events/AAMkSyntheticEvent1").to_return(status: 204)

    expect(client.delete("me/events/AAMkSyntheticEvent1")).to eq({})
  end

  it "raises NotFoundError for a 404" do
    stub_request(:get, calendar_url).to_return(graph_json_response("error_not_found", status: 404))

    expect { client.get("me/calendars/AAMkSyntheticCalendar1") }
      .to raise_error(MicrosoftGraph::NotFoundError) { |error| expect(error.status).to eq(404) }
  end

  it "raises Error for another failure" do
    stub_request(:post, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars").to_return(status: 400, body: "{}")

    expect { client.post("me/calendars", { name: "WIT Courses" }) }
      .to raise_error(MicrosoftGraph::Error) { |error| expect(error.status).to eq(400) }
  end

  it "refreshes an expired token before the request" do
    credential.update!(token_expires_at: 1.minute.ago, refresh_token: "refresh-me")
    stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL).to_return(graph_json_response("token_refresh"))
    stub = stub_request(:get, calendar_url)
           .with(headers: { "Authorization" => "Bearer synthetic-refreshed-access-token" })
           .to_return(graph_json_response("calendar_found"))

    client.get("me/calendars/AAMkSyntheticCalendar1")

    expect(stub).to have_been_requested
  end

  it "refreshes once and retries when Graph answers 401" do
    token_stub = stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL).to_return(graph_json_response("token_refresh"))
    stub_request(:get, calendar_url)
      .with(headers: { "Authorization" => "Bearer current-token" })
      .to_return(graph_json_response("error_unauthorized", status: 401))
    retried = stub_request(:get, calendar_url)
              .with(headers: { "Authorization" => "Bearer synthetic-refreshed-access-token" })
              .to_return(graph_json_response("calendar_found"))

    expect(client.get("me/calendars/AAMkSyntheticCalendar1")).to include("id" => "AAMkSyntheticCalendar1")
    expect(token_stub).to have_been_requested.once
    expect(retried).to have_been_requested.once
  end

  it "needs a credential" do
    expect { described_class.new(nil) }.to raise_error(MicrosoftGraph::AuthError)
  end
end
