# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Mcp", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:oauth_access_token, resource_owner_id: user.id) }
  let(:headers) do
    {
      "Content-Type"  => "application/json",
      "Accept"        => "application/json, text/event-stream",
      "Authorization" => "Bearer #{token.plaintext_token}"
    }
  end

  def rpc(method, params = {}, with: headers)
    post "/api/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: with
  end

  def tool_calls(tool, status)
    Yabeda.calendar.mcp_tool_calls_total.get(tool: tool, status: status) || 0
  end

  describe "the bearer token" do
    it "answers 401 with the resource metadata when there is no token" do
      rpc "tools/list", with: headers.except("Authorization")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("AUTH_MISSING")
      expect(response.headers["WWW-Authenticate"]).to eq(
        'Bearer resource_metadata="http://www.example.com/.well-known/oauth-protected-resource", scope="read"'
      )
    end

    it "answers 401 with invalid_token for an unknown token" do
      rpc "tools/list", with: headers.merge("Authorization" => "Bearer not-a-token")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("AUTH_INVALID")
      expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
    end

    it "does not take an extension JWT" do
      rpc "tools/list", with: headers.merge(auth_headers_for(user))

      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 401 with invalid_token for an expired token" do
      token.update!(created_at: 2.hours.ago)

      rpc "tools/list"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("AUTH_INVALID")
      expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
    end

    it "answers 401 for a revoked token" do
      token.revoke

      rpc "tools/list"

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
    end

    it "answers 403 for a token without the read scope" do
      token.update!(scopes: "")

      rpc "tools/list"

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["WWW-Authenticate"]).to include('error="insufficient_scope"')
    end
  end

  it "answers 405 to GET and DELETE" do
    get "/api/mcp", headers: headers
    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers["Allow"]).to eq("POST")

    delete "/api/mcp", headers: headers
    expect(response).to have_http_status(:method_not_allowed)
  end

  it "answers initialize with the server info" do
    rpc "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "1" } }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "serverInfo", "name")).to eq(McpTools::Server::NAME)
  end

  it "marks every tool read-only" do
    rpc "tools/list"

    tools = response.parsed_body.dig("result", "tools")
    expect(tools.map { |tool| tool.dig("annotations", "readOnlyHint") }).to all(be(true))
  end

  it "calls a tool as the token's user and counts the call" do
    term = create(:term)
    allow(Term).to receive(:current).and_return(term)

    expect { rpc "tools/call", { name: "my_courses", arguments: {} } }
      .to change { tool_calls("my_courses", "ok") }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "structuredContent")).to eq("term_uid" => term.uid, "courses" => [])
  end

  it "returns a tool error for a bad argument and counts it" do
    expect { rpc "tools/call", { name: "my_busy_times", arguments: { start_date: "soon", end_date: "2026-10-20" } } }
      .to change { tool_calls("my_busy_times", "error") }.by(1)

    result = response.parsed_body["result"]
    expect(result["isError"]).to be(true)
    expect(result.dig("content", 0, "text")).to eq("start_date must be a date in YYYY-MM-DD format")
  end

  it "counts an unknown tool in one bucket" do
    expect { rpc "tools/call", { name: "drop_tables", arguments: {} } }
      .to change { tool_calls("unknown", "error") }.by(1)
  end

  it "reports a tool that raises, and sends the client a generic error" do
    allow(BusyBlocks).to receive(:new).and_raise(RuntimeError, "database is down")

    reports = capture_error_reports do
      rpc "tools/call", { name: "my_busy_times", arguments: { start_date: "2026-10-19", end_date: "2026-10-20" } }
    end

    expect(reports.map { |report| report.error.class }).to eq([ RuntimeError ])
    expect(reports.first.handled).to be(true)
    expect(reports.first.context).to include(user_id: user.id, oauth_application_id: token.application_id)
    expect(response.body).not_to include("database is down")
  end
end
