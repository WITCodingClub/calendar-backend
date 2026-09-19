# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtensionUsage do
  describe ".record" do
    it "returns the number of events it counted" do
      counted = described_class.record(events: %w[passkey_created nope passkey_created], version: "4.0.1", browser: "firefox")

      expect(counted).to eq(2)
    end

    it "counts the event that the Outlook connect flow sends" do
      counted = described_class.record(events: %w[outlook_calendar_connected], version: "5.0.1", browser: "chrome")

      expect(counted).to eq(1)
    end

    it "counts no more than the per-request limit" do
      stub_const("ExtensionUsage::MAX_EVENTS_PER_REQUEST", 3)

      counted = described_class.record(events: Array.new(10, "calendar_link_copied"), version: "4.0.1", browser: "chrome")

      expect(counted).to eq(3)
    end
  end

  describe ExtensionUsage::VersionLabels do
    subject(:labels) { described_class.new(limit: 2) }

    it "keeps a well-formed version" do
      expect(labels.label_for("4.0.1")).to eq("4.0.1")
    end

    it "labels a malformed or missing version as unknown" do
      expect(labels.label_for("4.0.1-beta")).to eq("unknown")
      expect(labels.label_for(nil)).to eq("unknown")
    end

    it "labels new versions as other once the limit is reached, and keeps the ones it has seen" do
      labels.label_for("4.0.0")
      labels.label_for("4.0.1")

      expect(labels.label_for("9.9.9")).to eq("other")
      expect(labels.label_for("4.0.0")).to eq("4.0.0")
    end
  end
end
