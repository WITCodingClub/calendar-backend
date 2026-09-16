# frozen_string_literal: true

# Helpers for specs that exercise the Microsoft Graph calendar provider.
#
# Tag an example group with `:microsoft_graph` to give it a configured Entra
# client for the example. The values are placeholders, not real credentials.
module MicrosoftGraphHelpers
  GRAPH_URL = "https://graph.microsoft.com/v1.0"
  TOKEN_URL = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"

  CONFIGURED_ENV = {
    "MICROSOFT_CLIENT_ID"     => "test-client-id",
    "MICROSOFT_CLIENT_SECRET" => "test-client-secret"
  }.freeze

  def with_microsoft_graph_configured
    original = CONFIGURED_ENV.keys.index_with { |key| ENV[key] }
    ENV.update(CONFIGURED_ENV)
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def graph_fixture(name)
    file_fixture("microsoft_graph/#{name}.json").read
  end

  def graph_json_response(name, status: 200)
    { status: status, body: graph_fixture(name), headers: { "Content-Type" => "application/json" } }
  end
end

RSpec.configure do |config|
  config.include MicrosoftGraphHelpers

  config.around(:each, :microsoft_graph) do |example|
    with_microsoft_graph_configured { example.run }
  end
end
