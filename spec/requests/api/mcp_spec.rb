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
        "Bearer resource_metadata=\"http://www.example.com/.well-known/oauth-protected-resource\", " \
        "scope=\"#{McpTools::Scopes::NAMES.join(' ')}\""
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
    rpc "initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "spec", version: "1" } }

    expect(response).to have_http_status(:ok)
    server_info = response.parsed_body.dig("result", "serverInfo")
    expect(server_info["name"]).to eq(McpTools::Server::NAME)
    expect(server_info["description"]).to eq(McpTools::Server::DESCRIPTION)
    expect(server_info["icons"]).to eq([ { "src" => "http://example.com/icon.png", "mimeType" => "image/png", "sizes" => [ "180x180" ] } ])
    expect(response.parsed_body.dig("result", "instructions")).to include("program director", "academic advisor")
    expect(response.parsed_body.dig("result", "instructions")).to include("override", "dean's office of the school that offers the course")
    expect(response.parsed_body.dig("result", "instructions")).to include("time ticket", "Registration Alternate PIN (RAC)")
    expect(response.parsed_body.dig("result", "instructions")).to include("without being asked to by name")
  end

  it "keeps the instructions under the Claude Code limit, so no client cuts them" do
    expect(McpTools::Server::INSTRUCTIONS.length).to be <= McpTools::Server::MAX_INSTRUCTIONS_LENGTH
  end

  it "puts the registration rules for one tool in that tool's description" do
    expect(McpTools::SearchSections.description_value).to include("waitlist capacity of 0 means none")
    expect(McpTools::GetCourse.description_value).to include("min_grade")
    expect(McpTools::CheckSchedule.description_value).to include("time conflict override")
    expect(McpTools::GetDegreeRequirements.description_value).to include("course substitution")
  end

  describe "the MCP Apps extension" do
    let(:uri) { McpTools::WeekGridApp::URI_VALUE }

    it "declares the extension at initialize" do
      rpc "initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "spec", version: "1" } }

      expect(response.parsed_body.dig("result", "capabilities", "extensions", MCP::Apps::EXTENSION_ID))
        .to eq("mimeTypes" => [ MCP::Apps::RESOURCE_MIME_TYPE ])
    end

    it "links check_schedule and my_courses to the week grid in tools/list" do
      rpc "tools/list"

      tools = response.parsed_body.dig("result", "tools").index_by { |tool| tool["name"] }
      expect(tools.dig("check_schedule", "_meta", "ui", "resourceUri")).to eq(uri)
      expect(tools.dig("my_courses", "_meta", "ui", "resourceUri")).to eq(uri)
      expect(tools.dig("list_terms", "_meta")).to be_nil
    end

    it "lists the week grid in resources/list" do
      rpc "resources/list"

      expect(response.parsed_body.dig("result", "resources")).to contain_exactly(
        include("uri" => uri, "name" => "week_grid", "mimeType" => MCP::Apps::RESOURCE_MIME_TYPE)
      )
    end

    it "returns the template in resources/read" do
      rpc "resources/read", { uri: uri }

      contents = response.parsed_body.dig("result", "contents")
      expect(contents.size).to eq(1)
      expect(contents.first).to include("uri" => uri, "mimeType" => MCP::Apps::RESOURCE_MIME_TYPE)
      expect(contents.first["text"]).to start_with("<!DOCTYPE html>")
      expect(contents.first.dig("_meta", "ui")).to eq("prefersBorder" => true)
    end

    it "answers resources/read for an unknown URI with an error" do
      rpc "resources/read", { uri: "ui://wit-calendar/nothing" }

      expect(response.parsed_body.dig("error", "code")).to eq(-32602)
    end

    it "gives a client without the extension the same text and structured result" do
      term = create(:term)
      create(:course, term: term, crn: 20397)

      rpc "tools/call", { name: "check_schedule", arguments: { term_uid: term.uid, crns: [ 20397 ] } }

      result = response.parsed_body["result"]
      expect(result["isError"]).to be(false)
      expect(result.dig("structuredContent", "sections").pluck("crn")).to eq([ 20397 ])
      expect(JSON.parse(result.dig("content", 0, "text"))).to eq(result["structuredContent"])
    end
  end

  it "marks the read tools read-only and the write tools not destructive" do
    rpc "tools/list"

    tools = response.parsed_body.dig("result", "tools").index_by { |tool| tool["name"] }
    write_tools, read_tools = McpTools.all.partition { |tool| tool < McpTools::BaseWriteTool }

    expect(read_tools.map { |tool| tools.dig(tool.name_value, "annotations", "readOnlyHint") }).to all(be(true))
    expect(write_tools.map { |tool| tools.dig(tool.name_value, "annotations", "readOnlyHint") }).to all(be(false))
    expect(write_tools.map { |tool| tools.dig(tool.name_value, "annotations", "destructiveHint") }).to all(be(false))
  end

  it "gives each tool an outputSchema, with the advisory for an academic planning tool" do
    rpc "tools/list"

    tools = response.parsed_body.dig("result", "tools").index_by { |tool| tool["name"] }
    expect(McpTools.names.map { |name| tools.dig(name, "outputSchema", "type") }).to all(eq("object"))
    expect(tools.dig("list_terms", "outputSchema", "$schema")).to eq("https://json-schema.org/draft/2020-12/schema")
    expect(tools.dig("list_terms", "outputSchema", "required")).to eq(%w[current_term_uid next_term_uid terms])
    expect(tools.dig("get_section", "outputSchema", "required")).to include("crn", "advisory")
    expect(tools.dig("get_section", "outputSchema", "properties", "advisory", "properties").keys).to eq(%w[message data_sources])
    expect(tools.dig("list_friends", "outputSchema", "properties")).not_to have_key("advisory")
  end

  it "lists every tool to a token with any scope, and names the permission a write tool needs" do
    rpc "tools/list", with: headers.merge("Authorization" => "Bearer #{create(:oauth_access_token, resource_owner_id: user.id, scopes: 'catalog').plaintext_token}")

    tools = response.parsed_body.dig("result", "tools").index_by { |tool| tool["name"] }
    expect(tools.keys).to match_array(McpTools.names)
    expect(tools.dig("update_class_settings", "description")).to include('Needs the "Change calendar settings" permission')
    expect(tools.dig("list_terms", "description")).not_to include("permission")
  end

  it "keeps the tools of a token issued before the scopes were split" do
    legacy = create(:oauth_access_token, :legacy_read, resource_owner_id: user.id)

    rpc "tools/call", { name: "list_terms", arguments: {} }, with: headers.merge("Authorization" => "Bearer #{legacy.plaintext_token}")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "isError")).to be(false)
  end

  describe "a tool call without its scope" do
    def denials(scope, mode) = Yabeda.calendar.mcp_scope_denials_total.get(scope: scope, mode: mode) || 0

    it "answers a tool error that says how to add the permission, and counts it" do
      expect { rpc "tools/call", { name: "set_notifications", arguments: { disabled: true } } }
        .to change { denials("notifications:write", "tool_error") }.by(1)

      expect(response).to have_http_status(:ok)
      result = response.parsed_body["result"]
      expect(result["isError"]).to be(true)
      expect(result.dig("content", 0, "text")).to include('"Turn notifications off and on" permission', "connect again")
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "answers 403 insufficient_scope for a client that supports step-up authorization" do
      stub_const("McpTools::Scopes::STEP_UP_CLIENTS", [ token.application.uid ])

      expect { rpc "tools/call", { name: "set_notifications", arguments: { disabled: true } } }
        .to change { denials("notifications:write", "step_up") }.by(1)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("INSUFFICIENT_SCOPE")
      expect(response.headers["WWW-Authenticate"]).to include(
        'error="insufficient_scope"',
        "scope=\"#{McpTools::Scopes::LEGACY_READ_SCOPES.join(' ')} notifications:write\""
      )
    end

    it "does not challenge a step-up client for a tool the token can call" do
      stub_const("McpTools::Scopes::STEP_UP_CLIENTS", [ token.application.uid ])

      rpc "tools/call", { name: "list_terms", arguments: {} }

      expect(response).to have_http_status(:ok)
    end
  end

  it "calls a tool as the token's user and counts the call" do
    term = create(:term)
    allow(Term).to receive(:current).and_return(term)

    expect { rpc "tools/call", { name: "my_courses", arguments: {} } }
      .to change { tool_calls("my_courses", "ok") }.by(1)

    expect(response).to have_http_status(:ok)
    content = response.parsed_body.dig("result", "structuredContent")
    expect(content.except("advisory")).to eq("term_uid" => term.uid, "term_name" => term.name, "courses" => [])
    expect(content.dig("advisory", "message")).to eq(McpTools::BaseTool::ADVISORY)
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

  describe "prompts" do
    it "declares prompts and completions in initialize" do
      rpc "initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "spec", version: "1" } }

      capabilities = response.parsed_body.dig("result", "capabilities")
      expect(capabilities).to include("prompts", "completions", "tools")
    end

    it "lists every prompt with its arguments" do
      rpc "prompts/list"

      prompts = response.parsed_body.dig("result", "prompts").index_by { |prompt| prompt["name"] }
      expect(prompts.keys).to eq(McpTools::Prompts.names)
      expect(prompts.dig("plan_term_schedule", "arguments").pluck("name")).to eq(%w[term courses preferences])
      expect(prompts.dig("plan_term_schedule", "arguments").pluck("required")).to all(be(false))
    end

    it "gets a prompt with no arguments" do
      rpc "prompts/get", { name: "check_my_schedule" }

      expect(response).to have_http_status(:ok)
      message = response.parsed_body.dig("result", "messages", 0)
      expect(message["role"]).to eq("user")
      expect(message.dig("content", "text")).to include("my_courses", "program director", "academic advisor")
    end

    it "gets a prompt with arguments" do
      term = create(:term, year: 2031, season: :spring)

      rpc "prompts/get", { name: "plan_term_schedule", arguments: { term: term.uid.to_s, courses: "COMP 2350" } }

      text = response.parsed_body.dig("result", "messages", 0, "content", "text")
      expect(text).to include("Term: Spring 2031 (term_uid #{term.uid}).", "Courses I want: COMP 2350.")
      expect(response.parsed_body["result"]).not_to include("ttlMs", "cacheScope")
    end

    it "answers invalid params for an unknown prompt" do
      rpc "prompts/get", { name: "drop_tables" }

      expect(response.parsed_body.dig("error", "code")).to eq(-32_602)
    end

    it "answers invalid params, with no error report, for arguments that are not an object of text" do
      [ "COMP 2350", [ "COMP 2350" ], { courses: [ "COMP 2350" ] } ].each do |arguments|
        reports = capture_error_reports { rpc "prompts/get", { name: "plan_term_schedule", arguments: arguments } }

        expect(response.parsed_body.dig("error", "code")).to eq(-32_602)
        expect(reports).to be_empty
      end
    end
  end

  describe "completion/complete" do
    def complete(prompt, argument, value)
      rpc "completion/complete", { ref: { type: "ref/prompt", name: prompt }, argument: { name: argument, value: value } }
      response.parsed_body.dig("result", "completion")
    end

    it "completes a course code" do
      create(:catalog_course, subject_code: "COMP", course_number: 2350)

      expect(complete("plan_term_schedule", "courses", "comp 2")).to eq("values" => [ "COMP 2350" ], "hasMore" => false)
    end

    it "completes a term uid" do
      term = create(:term)

      expect(complete("check_my_schedule", "term", term.uid.to_s)["values"]).to eq([ term.uid.to_s ])
    end

    it "gives no values for an argument with no completions" do
      expect(complete("plan_degree_progression", "program", "BS")).to eq("values" => [], "hasMore" => false)
    end

    it "completes a subject in the term the client sends as context" do
      term = create(:term, year: 2031, season: :spring)
      create(:course, term: term, subject: "Computer Science (COMP)")
      create(:course, subject: "Communication (COMM)")

      rpc "completion/complete", { ref: { type: "ref/prompt", name: "find_class_for_free_time" },
                                   argument: { name: "subject", value: "co" },
                                   context: { arguments: { term: "Spring 2031" } } }

      expect(response.parsed_body.dig("result", "completion")).to eq("values" => [ "COMP" ], "hasMore" => false)
    end

    it "answers a malformed context with values and no error report" do
      create(:course, subject: "Computer Science (COMP)")
      allow(Term).to receive(:current).and_return(nil)

      [ "text", [ 1 ], { arguments: "text" }, { arguments: [ 1 ] } ].each do |context|
        reports = capture_error_reports do
          rpc "completion/complete", { ref: { type: "ref/prompt", name: "find_class_for_free_time" },
                                       argument: { name: "subject", value: "co" }, context: context }
        end

        expect(response.parsed_body.dig("result", "completion", "values")).to eq([ "COMP" ])
        expect(reports).to be_empty
      end
    end
  end

  describe "cache hints" do
    let(:hints) { { "ttlMs" => 300_000, "cacheScope" => "public" } }

    it "marks tools/list, prompts/list, resources/list, and resources/read public for 5 minutes" do
      [ [ "tools/list", {} ], [ "prompts/list", {} ], [ "resources/list", {} ],
        [ "resources/read", { uri: McpTools::WeekGridApp::URI_VALUE } ] ].each do |method, params|
        rpc method, params

        expect(response.parsed_body["result"]).to include(hints)
      end
    end

    it "adds no hints to prompts/get or completion/complete" do
      rpc "prompts/get", { name: "check_my_schedule" }
      expect(response.parsed_body["result"]).not_to include("ttlMs", "cacheScope")

      rpc "completion/complete", { ref: { type: "ref/prompt", name: "check_my_schedule" }, argument: { name: "term", value: "" } }
      expect(response.parsed_body["result"]).not_to include("ttlMs", "cacheScope")
    end

    it "gives the same tools/list to tokens of different students and scopes" do
      rpc "tools/list"
      first = response.parsed_body["result"]

      other = create(:oauth_access_token, resource_owner_id: create(:user).id, scopes: "catalog")
      rpc "tools/list", with: headers.merge("Authorization" => "Bearer #{other.plaintext_token}")

      expect(response.parsed_body["result"]).to eq(first)
    end

    it "adds no hints to a tool call" do
      rpc "tools/call", { name: "list_terms", arguments: {} }

      expect(response.parsed_body["result"]).not_to include("ttlMs", "cacheScope")
    end

    it "still lists the tools and prompts, with the hints, on an older protocol version" do
      older = headers.merge("MCP-Protocol-Version" => "2025-03-26")

      rpc "tools/list", with: older
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("result", "tools").pluck("name")).to match_array(McpTools.names)

      rpc "prompts/list", with: older
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["result"]).to include(hints)
      expect(response.parsed_body.dig("result", "prompts").pluck("name")).to eq(McpTools::Prompts.names)
    end
  end
end
