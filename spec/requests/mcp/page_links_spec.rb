# frozen_string_literal: true

require "rails_helper"

# Calls each tool with page links over /api/mcp, then opens each link as the
# signed-in student. A link to a page that does not exist, or that a student
# cannot open, fails here.
RSpec.describe "MCP page links", type: :request do
  let(:user)   { create(:user, :with_processed_courses) }
  let(:friend) { create(:user) }
  let(:term)   { user.enrollments.first.term }
  let(:token)  { create(:oauth_access_token, :all_scopes, resource_owner_id: user.id) }

  let(:calls) do
    {
      "my_courses"               => { term_uid: term.uid },
      "list_friends"             => {},
      "friend_busy_times"        => { friend_id: friend.public_id, start_date: "2026-12-17", end_date: "2026-12-18" },
      "my_calendar_settings"     => {},
      "update_calendar_settings" => { level: "all_classes", color: "sage" },
      "set_notifications"        => { disabled: true }
    }
  end

  def call_tool(name, arguments, scopes: token, version: "2025-06-18")
    headers = {
      "Content-Type"  => "application/json",
      "Accept"        => "application/json, text/event-stream",
      "Authorization" => "Bearer #{scopes.plaintext_token}"
    }
    headers["MCP-Protocol-Version"] = version if version
    post "/api/mcp",
         params:  { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
         headers: headers
    response.parsed_body["result"]
  end

  def links(result) = result["content"].select { |item| item["type"] == "resource_link" }

  before do
    friendship = create(:friendship, :accepted, requester: user, addressee: friend)
    friendship.update_visibility_for!(friend, :availability_only)
  end

  it "covers every tool with links" do
    expect(McpTools.all.select(&:links_block).map(&:name_value)).to match_array(calls.keys)
  end

  it "sends the JSON text first, then links to pages that open for the student" do
    uris = calls.flat_map do |name, arguments|
      result = call_tool(name, arguments)

      expect(result["isError"]).to be(false), "#{name}: #{result.dig('content', 0, 'text')}"
      expect(result.dig("content", 0, "type")).to eq("text")
      expect(JSON.parse(result.dig("content", 0, "text"))).to eq(result["structuredContent"])
      expect(links(result)).to be_present, name
      expect(links(result)).to all(include("name", "title", "mimeType" => "text/html"))
      links(result).pluck("uri")
    end

    sign_in user
    uris.uniq.each do |uri|
      get URI(uri).request_uri

      expect(response).to have_http_status(:ok), "#{uri} answered #{response.status}"
    end
  end

  it "links a missing permission to the connected apps card of the settings page" do
    read_only = create(:oauth_access_token, resource_owner_id: user.id)

    result = call_tool("set_notifications", { disabled: true }, scopes: read_only)

    expect(result["isError"]).to be(true)
    link = links(result).sole
    uri  = URI(link["uri"])
    expect(uri.fragment).to eq(McpTools::PageLinks::CONNECTED_APPS_ANCHOR)

    sign_in user
    get uri.request_uri

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("##{uri.fragment}").text).to include("Connected apps", read_only.application.name)
  end

  describe "the MCP-Protocol-Version header" do
    let(:read_only) { create(:oauth_access_token, resource_owner_id: user.id) }

    it "gives links to a 2025-06-18 client" do
      expect(links(call_tool("list_friends", {}))).to be_present
      expect(links(call_tool("set_notifications", { disabled: true }, scopes: read_only))).to be_present
    end

    it "gives only the text to a 2025-03-26 client and to a request with no header" do
      [ "2025-03-26", nil ].each do |version|
        result = call_tool("list_friends", {}, version: version)
        expect(result["content"].pluck("type")).to eq([ "text" ]), version.inspect

        error = call_tool("set_notifications", { disabled: true }, scopes: read_only, version: version)
        expect(error["content"].pluck("type")).to eq([ "text" ]), version.inspect
      end
    end
  end

  it "opens the friend page of a friend who shares the full schedule" do
    Flipper.enable_actor(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, user)
    Friendship.accepted_between(user, friend).update_visibility_for!(friend, :full)

    uri = links(call_tool("friend_busy_times", calls["friend_busy_times"])).sole["uri"]
    sign_in user
    get URI(uri).request_uri

    expect(response).to have_http_status(:ok)
  ensure
    Flipper.disable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY)
  end
end
