# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::Scopes do
  it "matches the Doorkeeper configuration" do
    expect(Doorkeeper.config.scopes.to_a).to match_array(described_class::NAMES + [ described_class::LEGACY_READ ])
    expect(Doorkeeper.config.default_scopes.to_a).to eq([ described_class::ALWAYS ])
  end

  it "gives every tool a scope from the list" do
    McpTools.all.each do |tool|
      expect(described_class::NAMES).to include(tool.required_scope), "#{tool.name_value} names no scope"
    end
  end

  it "refuses a scope that is not in the list" do
    expect { Class.new(McpTools::BaseTool) { requires_scope "admin" } }.to raise_error(ArgumentError, /admin/)
  end

  describe ".expand" do
    it "turns the legacy read scope into every read scope" do
      expect(described_class.expand("read")).to match_array(described_class::LEGACY_READ_SCOPES)
    end

    it "keeps the named scopes and drops unknown ones" do
      expect(described_class.expand("catalog settings:write admin")).to eq(%w[catalog settings:write])
    end

    it "gives nothing for no scope" do
      expect(described_class.expand(nil)).to eq([])
    end
  end

  describe ".step_up?" do
    it "matches a client by its uid or its name, and nothing by default" do
      application = build(:oauth_application, uid: "https://client.example/m.json", name: "Example")

      expect(described_class.step_up?(application)).to be(false)
      expect(described_class.step_up?(nil)).to be(false)

      stub_const("McpTools::Scopes::STEP_UP_CLIENTS", [ "https://client.example/m.json" ])
      expect(described_class.step_up?(application)).to be(true)

      stub_const("McpTools::Scopes::STEP_UP_CLIENTS", [ "Example" ])
      expect(described_class.step_up?(application)).to be(true)
    end
  end
end
