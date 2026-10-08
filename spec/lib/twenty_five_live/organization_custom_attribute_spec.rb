# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLive::OrganizationCustomAttribute do
  describe ".find_by_id" do
    it "returns the Mission attribute" do
      attribute = described_class.find_by_id(38)

      expect(attribute).to have_attributes(name: "Mission", attribute_type: "X",
                                           attribute_type_name: "Long Text", sort_order: 1)
      expect(attribute).to be_active
    end

    it "returns nil for an unknown id" do
      expect(described_class.find_by_id(999)).to be_nil
    end
  end

  describe ".all" do
    it "returns the attributes in 25Live sort order" do
      expect(described_class.all.map(&:id)).to eq([ 38, 5, 6, -11, -8 ])
    end
  end
end
