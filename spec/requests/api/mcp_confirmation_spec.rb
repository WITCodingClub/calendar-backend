# frozen_string_literal: true

require "rails_helper"

# A write tool asks the student to confirm through the client
# (McpTools::Confirmation), over the real transport and the sealed request
# state of the SDK.
RSpec.describe "Api::Mcp confirmation of a write tool", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)  { create(:user) }
  let(:token) { create(:oauth_access_token, :all_scopes, resource_owner_id: user.id) }
  let(:elicitation) { { elicitation: { form: {} } } }
  let(:arguments) { { disabled: true, duration_hours: 2 } }

  def headers_for(access_token, modern:, tool: "set_notifications")
    headers = {
      "Content-Type"  => "application/json",
      "Accept"        => "application/json, text/event-stream",
      "Authorization" => "Bearer #{access_token.plaintext_token}"
    }
    return headers unless modern

    headers.merge("MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/call", "Mcp-Name" => tool)
  end

  # A tools/call on the 2026-07-28 wire, with the client capabilities in _meta.
  def modern_call(capabilities: elicitation, args: arguments, retry_with: nil, access_token: token, tool: "set_notifications")
    params = {
      name:      tool,
      arguments: args,
      _meta:     {
        "io.modelcontextprotocol/protocolVersion"    => "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities" => capabilities
      }
    }
    params.merge!(retry_with) if retry_with
    post "/api/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: params }.to_json,
                     headers: headers_for(access_token, modern: true, tool: tool)
    response.parsed_body
  end

  def legacy_call
    post "/api/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "set_notifications", arguments: arguments } }.to_json,
                     headers: headers_for(token, modern: false)
    response.parsed_body
  end

  def question_state = modern_call.dig("result", "requestState")

  def answer(action, state: question_state, **options)
    modern_call(retry_with: { inputResponses: mcp_confirmation(action), requestState: state }, **options)
  end

  def expect_refused_state(body)
    expect(response).to have_http_status(:bad_request)
    expect(body.dig("error", "code")).to eq(-32602)
    expect(body.dig("error", "message")).to eq("Invalid or expired requestState")
    expect(user.reload.notifications_disabled?).to be(false)
  end

  describe "a client that cannot answer" do
    it "makes the change on the legacy wire, as before" do
      result = legacy_call["result"]

      expect(result["isError"]).to be(false)
      expect(result).not_to have_key("resultType")
      expect(user.reload.notifications_disabled?).to be(true)
    end

    it "makes the change on the 2026-07-28 wire when the client did not declare elicitation" do
      result = modern_call(capabilities: {})["result"]

      expect(result).to include("resultType" => "complete", "isError" => false)
      expect(user.reload.notifications_disabled?).to be(true)
    end
  end

  describe "a client that declared form elicitation" do
    it "gets an input_required result with a sealed state, and nothing changes" do
      result = modern_call["result"]

      expect(response).to have_http_status(:ok)
      expect(result["resultType"]).to eq("input_required")
      expect(result.dig("inputRequests", "confirm", "method")).to eq("elicitation/create")
      expect(result.dig("inputRequests", "confirm", "params", "message")).to start_with("Turn off the reminders")
      expect(result["requestState"]).to start_with("v1.")
      expect(result["requestState"]).not_to include(user.id.to_s)
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "makes the change when the student accepts" do
      result = answer("accept")["result"]

      expect(result).to include("resultType" => "complete", "isError" => false)
      expect(result.dig("structuredContent", "notifications_disabled")).to be(true)
      expect(user.reload.notifications_disabled?).to be(true)
    end

    it "changes nothing, with a normal result, when the student declines or cancels" do
      { "decline" => "declined", "cancel" => "cancelled" }.each do |action, reason|
        result = answer(action)["result"]

        expect(result).to include("resultType" => "complete", "isError" => false)
        expect(result.dig("structuredContent", "not_changed", "reason")).to eq(reason)
      end
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "refuses a changed state and does not report it" do
      state = question_state
      tampered = state[0..-3] + (state[-2] == "A" ? "B" : "A") + state[-1]

      reports = capture_error_reports { expect_refused_state(answer("accept", state: tampered)) }
      expect(reports).to be_empty
    end

    it "refuses an expired state" do
      state = question_state

      travel(McpTools::Server::REQUEST_STATE_TTL + 1) { expect_refused_state(answer("accept", state: state)) }
    end

    it "refuses the state of another student" do
      state = question_state
      other_token = create(:oauth_access_token, :all_scopes, resource_owner_id: create(:user).id)

      body = answer("accept", state: state, access_token: other_token)

      expect(response).to have_http_status(:bad_request)
      expect(body.dig("error", "message")).to eq("Invalid or expired requestState")
      expect(User.where.not(notifications_disabled_until: nil)).to be_empty
    end

    it "refuses the state of a call with other arguments" do
      state = question_state

      expect_refused_state(answer("accept", state: state, args: { disabled: true, duration_hours: 200 }))
    end

    it "refuses the state of another tool" do
      state = question_state

      body = answer("accept", state: state, tool: "update_calendar_settings", args: arguments)

      expect(response).to have_http_status(:bad_request)
      expect(body.dig("error", "message")).to eq("Invalid or expired requestState")
    end

    it "answers a missing scope with the tool error, before it asks" do
      no_write = create(:oauth_access_token, resource_owner_id: user.id, scopes: "catalog")

      result = modern_call(access_token: no_write)["result"]

      expect(result).to include("resultType" => "complete", "isError" => true)
      expect(result.dig("content", 0, "text")).to include("permission")
    end
  end
end
