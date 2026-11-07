# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLive::OrganizationCategory do
  describe ".find_by_id" do
    it "returns the Leopard In Training category" do
      category = described_class.find_by_id(126)

      expect(category).to have_attributes(name: "Student Club - Leopard In Training", sort_order: 1)
      expect(category).to be_active
    end

    it "returns nil for an unknown id" do
      expect(described_class.find_by_id(999)).to be_nil
    end
  end

  describe ".all" do
    it "returns the categories in 25Live sort order" do
      categories = described_class.all

      expect(categories.first.id).to eq(126)
      expect(categories.map(&:sort_order)).to eq((1..25).to_a)
    end
  end
end
