# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::Reminders do
  describe ".for_sync" do
    it "turns each reminder into minutes before the start" do
      reminders = described_class.for_sync([
        { "time" => "30", "type" => "minutes", "method" => "popup" },
        { "time" => "2", "type" => "hours", "method" => "email" },
        { "time" => "1", "type" => "days", "method" => "notification" }
      ])

      expect(reminders.map(&:minutes)).to eq([ 30, 120, 1440 ])
      expect(reminders.map(&:delivery)).to eq(%w[popup email popup])
    end

    it "leaves out an entry that does not follow the rules" do
      reminders = described_class.for_sync([
        { "time" => "30", "type" => "minutes", "method" => "sms" },
        { "time" => "", "type" => "minutes", "method" => "popup" },
        "popup"
      ])

      expect(reminders).to eq([])
    end

    it "gives nil for a setting that is not a list" do
      expect(described_class.for_sync(nil)).to be_nil
    end

    # Rows saved before the type check can hold another type.
    it "counts an unknown type as minutes" do
      expect(described_class.for_sync([ { "time" => "10", "type" => "weeks", "method" => "popup" } ]))
        .to eq([ described_class::Reminder.new(delivery: "popup", minutes: 10) ])
    end

    it "leaves out a reminder with no type" do
      expect(described_class.for_sync([ { "time" => "10", "type" => "", "method" => "popup" } ])).to eq([])
    end
  end
end
