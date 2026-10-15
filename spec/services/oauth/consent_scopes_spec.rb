# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::ConsentScopes do
  let(:all) { McpTools::Scopes::NAMES.join(" ") }

  def checked(consent) = consent.groups.values.flatten.select(&:checked).map { |item| item.scope.name }
  def shown(consent)   = consent.groups.values.flatten.map { |item| item.scope.name }

  it "shows a box for each requested scope except the always-on one, read boxes checked" do
    consent = described_class.new(all)

    expect(shown(consent)).to eq(McpTools::Scopes::NAMES - [ "catalog" ])
    expect(consent.groups.keys).to eq(%i[read change])
    expect(checked(consent)).to eq(%w[schedule:read friends:read settings:read])
  end

  it "checks a change scope the student gave this app before" do
    consent = described_class.new(all, previous: "catalog settings:write")

    expect(checked(consent)).to include("settings:write")
    expect(checked(consent)).not_to include("notifications:write")
  end

  it "checks every box of a request for fewer than all scopes, such as a step-up" do
    consent = described_class.new("catalog schedule:read notifications:write")

    expect(shown(consent)).to eq(%w[schedule:read notifications:write])
    expect(checked(consent)).to eq(%w[schedule:read notifications:write])
  end

  it "turns the legacy read scope into the read scopes" do
    consent = described_class.new("read")

    expect(consent.requested_scope).to eq("catalog schedule:read friends:read settings:read")
    expect(consent.groups).not_to have_key(:change)
  end

  it "asks for the always-on scope alone when the request names none" do
    consent = described_class.new(nil)

    expect(consent.requested_scope).to eq("catalog")
    expect(consent.groups).to be_empty
  end

  describe "#granted_scope" do
    it "keeps the always-on scope and the checked boxes, in list order" do
      consent = described_class.new(all)

      expect(consent.granted_scope(%w[settings:write schedule:read])).to eq("catalog schedule:read settings:write")
    end

    it "ignores a checked scope the client did not ask for" do
      consent = described_class.new("catalog schedule:read")

      expect(consent.granted_scope(%w[schedule:read friends:groups])).to eq("catalog schedule:read")
    end

    it "grants the always-on scope with no boxes" do
      expect(described_class.new(all).granted_scope(nil)).to eq("catalog")
    end
  end
end
