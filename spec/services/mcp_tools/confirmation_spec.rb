# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::Confirmation do
  let(:user) { create(:user) }
  let(:message) { "Change the calendar events of all your classes:\n- Color: from not set to Sage." }

  def confirm(context) = described_class.new(context, user: user).call(message)

  def question = confirm(mcp_modern_context(user))

  def answer(response, state: question.request_state)
    confirm(mcp_modern_context(user, input_responses: response, request_state: state))
  end

  describe "a client that cannot answer" do
    it "accepts on the legacy wire, which gives a Hash context" do
      expect(confirm(mcp_context(user))).to eq(:accept)
    end

    it "accepts on the 2026-07-28 wire when the client did not declare elicitation" do
      expect(confirm(mcp_modern_context(user, capabilities: {}))).to eq(:accept)
    end

    it "accepts when the client declared only URL elicitation" do
      expect(confirm(mcp_modern_context(user, capabilities: { elicitation: { url: {} } }))).to eq(:accept)
    end

    it "accepts when there is no context" do
      expect(confirm(nil)).to eq(:accept)
    end
  end

  describe "a client that declared form elicitation" do
    it "asks with the message and a boolean confirm field" do
      result = question

      expect(result).to be_a(MCP::Server::InputRequiredResult)
      request = result.input_requests.fetch(described_class::KEY)
      expect(request[:method]).to eq("elicitation/create")
      expect(request[:params]).to include(mode: "form", message: message)
      expect(request.dig(:params, :requestedSchema, :properties, :confirm, :type)).to eq("boolean")
      expect(request.dig(:params, :requestedSchema, :required)).to eq([ "confirm" ])
    end

    it "asks when the bare elicitation capability implies form" do
      expect(confirm(mcp_modern_context(user, capabilities: { "elicitation" => {} }))).to be_a(MCP::Server::InputRequiredResult)
    end

    it "accepts when the student checks the box" do
      expect(answer(mcp_confirmation("accept"))).to eq(:accept)
    end

    it "declines when the student accepts the form with the box clear, or declines it" do
      expect(answer(mcp_confirmation("accept", confirm: false))).to eq(:decline)
      expect(answer(mcp_confirmation("decline"))).to eq(:decline)
    end

    it "cancels when the student cancels, or the answer is missing or unknown" do
      expect(answer(mcp_confirmation("cancel"))).to eq(:cancel)
      expect(answer(nil)).to eq(:cancel)
      expect(answer({ described_class::KEY => { action: "maybe" } })).to eq(:cancel)
    end

    it "reads string keys too" do
      expect(answer({ "confirm" => { "action" => "accept", "content" => { "confirm" => true } } })).to eq(:accept)
    end

    it "asks again for an answer with no state, because the student did not see this question" do
      expect(answer(mcp_confirmation("accept"), state: nil)).to be_a(MCP::Server::InputRequiredResult)
    end

    it "asks again when the state is for another user, another message, or not JSON" do
      real = JSON.parse(question.request_state)
      other_user = JSON.generate(real.merge("u" => create(:user).id))
      other_message = JSON.generate(real.merge("d" => OpenSSL::Digest::SHA256.hexdigest("Something else")))

      expect(answer(mcp_confirmation("accept"), state: JSON.generate(real))).to eq(:accept)
      [ other_user, other_message, "not json", "[]" ].each do |state|
        expect(answer(mcp_confirmation("accept"), state: state)).to be_a(MCP::Server::InputRequiredResult)
      end
    end

    it "asks again when the record changed since the question" do
      state = described_class.new(mcp_modern_context(user), user: user).call(message, version: "v1").request_state
      context = mcp_modern_context(user, input_responses: mcp_confirmation("accept"), request_state: state)

      expect(described_class.new(context, user: user).call(message, version: "v1")).to eq(:accept)
      expect(described_class.new(context, user: user).call(message, version: "v2")).to be_a(MCP::Server::InputRequiredResult)
      expect(described_class.new(context, user: user).call(message)).to be_a(MCP::Server::InputRequiredResult)
    end

    it "treats a state that is not a String as no state" do
      [ 42, { "u" => user.id }, [ "x" ] ].each do |state|
        expect(answer(mcp_confirmation("accept"), state: state)).to be_a(MCP::Server::InputRequiredResult)
      end
    end

    it "treats an answer or content that is not an object as a cancel" do
      [ "accept", [ 1 ], 42, { action: "accept", content: "yes" }, { action: "accept", content: [ true ] },
        { action: "accept" } ].each do |response|
        expect(answer({ described_class::KEY => response })).to eq(:cancel)
      end
    end

    it "treats inputResponses that are not an object as no answer" do
      expect(answer("accept")).to eq(:cancel)
      expect(answer([ 1, 2 ])).to eq(:cancel)
    end
  end
end
