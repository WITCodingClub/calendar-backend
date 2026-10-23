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

    it "does not take the same state and answer again after the change is undone" do
      state = question_state
      expect(answer("accept", state: state).dig("result", "isError")).to be(false)
      travel(1.second) { user.reload.enable_notifications! }

      body = answer("accept", state: state)

      expect(body.dig("result", "resultType")).to eq("input_required")
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "does not raise for an answer or state that is not an object" do
      reports = capture_error_reports do
        modern_call(retry_with: { inputResponses: "accept", requestState: question_state })
        expect(response.parsed_body.dig("result", "structuredContent", "not_changed", "reason")).to eq("cancelled")

        modern_call(retry_with: { inputResponses: { confirm: { action: "accept", content: "yes" } }, requestState: question_state })
        expect(response.parsed_body.dig("result", "structuredContent", "not_changed", "reason")).to eq("cancelled")

        modern_call(retry_with: { inputResponses: mcp_confirmation("accept"), requestState: 42 })
        expect(response).to have_http_status(:bad_request)
      end

      expect(reports).to be_empty
      expect(user.reload.notifications_disabled?).to be(false)
    end
  end

  describe "the tool call count" do
    def tool_calls(status, tool: "set_notifications")
      Yabeda.calendar.mcp_tool_calls_total.get(tool: tool, status: status) || 0
    end

    it "counts the question, an accept, a decline, and a cancel by status" do
      expect { question_state }.to change { tool_calls("input_required") }.by(1)
      expect { answer("decline") }.to change { tool_calls("declined") }.by(1)
      expect { answer("cancel") }.to change { tool_calls("cancelled") }.by(1)
      expect { answer("accept") }.to change { tool_calls("ok") }.by(1)
    end

    it "counts a refused state under the tool that the request names" do
      state = question_state

      unknown = tool_calls("error", tool: "unknown")

      expect { answer("accept", state: "#{state}x") }.to change { tool_calls("error") }.by(1)
      expect(tool_calls("error", tool: "unknown")).to eq(unknown)
    end
  end

  describe "the settings tools" do
    let(:course) { create(:course, title: "Data Structures") }
    let(:meeting_time) { create(:course_meeting_time, course: course) }

    before { create(:enrollment, user: user, course: course) }

    it "asks, then saves the class settings on accept" do
      args = { meeting_time_id: meeting_time.public_id, color: "sage" }
      result = modern_call(tool: "update_class_settings", args: args)["result"]

      expect(result["resultType"]).to eq("input_required")
      expect(result.dig("inputRequests", "confirm", "params", "message"))
        .to start_with("Change the calendar events of one class only (Data Structures")
      expect(EventPreference.count).to eq(0)

      saved = answer("accept", state: result["requestState"], tool: "update_class_settings", args: args)["result"]

      expect(saved.dig("structuredContent", "result")).to eq("saved")
      expect(EventPreference.sole.color_id).to eq(GoogleCalendar::Colors::SAGE)
    end

    it "asks, then keeps the calendar settings on decline" do
      args = { level: "all_classes", visibility: "private" }
      result = modern_call(tool: "update_calendar_settings", args: args)["result"]

      expect(result.dig("inputRequests", "confirm", "params", "message")).to include("- Visibility: from not set to private.")

      declined = answer("decline", state: result["requestState"], tool: "update_calendar_settings", args: args)["result"]

      expect(declined.dig("structuredContent", "result")).to eq("unchanged")
      expect(declined.dig("structuredContent", "not_changed", "reason")).to eq("declined")
      expect(CalendarPreference.count).to eq(0)
    end

    it "changes the settings at once for a legacy client" do
      post "/api/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                                 params: { name: "update_calendar_settings", arguments: { level: "lecture", color: "basil" } } }.to_json,
                       headers: headers_for(token, modern: false)

      expect(response.parsed_body.dig("result", "structuredContent", "result")).to eq("saved")
      expect(CalendarPreference.sole.color_id).to eq(GoogleCalendar::Colors::BASIL)
    end
  end
end
