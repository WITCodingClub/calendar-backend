# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CoursesHelper do
  describe "#admin_open_count" do
    it "gives the open seats and the capacity" do
      expect(helper.admin_open_count(4, 24)).to eq("4 of 24 open")
    end

    it "keeps a negative count for an over-enrolled section" do
      expect(helper.admin_open_count(-2, 24)).to eq("-2 of 24 open")
    end

    it "gives nil when Banner gave no counts" do
      expect([ helper.admin_open_count(nil, 24), helper.admin_open_count(4, nil) ]).to eq([ nil, nil ])
    end
  end

  describe "#admin_fee" do
    it "gives the description, the level, and the amount in dollars" do
      fee = { "description" => "Follett Access", "level" => "Undergraduate", "amount_cents" => 9500 }

      expect(helper.admin_fee(fee)).to eq("Follett Access (Undergraduate): $95.00")
    end

    it "names a fee with no description or level" do
      expect(helper.admin_fee({ "amount_cents" => 1250 })).to eq("Fee: $12.50")
    end
  end
end
