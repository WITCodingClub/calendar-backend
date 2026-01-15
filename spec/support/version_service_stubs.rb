# frozen_string_literal: true

require "webmock/rspec"

# Stub GitHub API calls for VersionService to prevent real HTTP requests in tests
RSpec.configure do |config|
  config.before do
    # Stub the releases endpoint
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar-backend/releases/latest")
      .to_return(
        status: 200,
        body: { tag_name: "v1.0.2" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub the tags endpoint (fallback)
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar-backend/tags")
      .to_return(
        status: 200,
        body: [{ name: "v1.0.2" }, { name: "v1.0.1" }].to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
