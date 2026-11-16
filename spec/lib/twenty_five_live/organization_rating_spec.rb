# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLive::OrganizationRating do
  it "finds each listed row by its 25Live id" do
    described_class.all.each do |row|
      expect(row).to have_attributes(id: be_present, name: be_present, sort_order: be_present)
      expect(described_class.find_by_id(row.id)).to have_attributes(name: row.name, sort_order: row.sort_order)
    end
  end

  it "returns nil for an unknown id" do
    expect(described_class.find_by_id(999)).to be_nil
  end
end
