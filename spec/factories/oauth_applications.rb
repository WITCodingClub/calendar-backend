# frozen_string_literal: true

# An OAuth client of the MCP server (docs/mcp.md). The model is Doorkeeper's.
FactoryBot.define do
  factory :oauth_application, class: "Doorkeeper::Application" do
    name { Faker::App.name }
    redirect_uri { "https://#{Faker::Internet.domain_name}/callback" }
    scopes { McpTools::Scopes::NAMES.join(" ") }
    confidential { false }

    trait :dynamic do
      dynamic { true }
    end
  end
end
