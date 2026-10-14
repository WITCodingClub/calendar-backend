# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLive::OrganizationRating do
  describe ".find_by_id" do
    it "returns the None rating" do
      rating = described_class.find_by_id(6)

      expect(rating).to have_attributes(name: "None", sort_order: 1)
      expect(rating).to be_active
    end

    it "returns nil for an unknown id" do
      expect(described_class.find_by_id(999)).to be_nil
    end
  end

  describe ".all" do
    it "returns the ratings in 25Live sort order" do
      expect(described_class.all.map(&:id)).to eq([ 6, 2, 3, 4, 5 ])
      expect(described_class.all.map(&:sort_order)).to eq([ 1, 2, 3, 4, 5 ])
    end
  end
end
