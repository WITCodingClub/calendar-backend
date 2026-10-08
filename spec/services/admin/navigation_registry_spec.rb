# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::NavigationRegistry do
  let(:items) { described_class::CATEGORIES.flat_map { |category| category[:items] } }

  it "gives every item an icon that AdminHelper can draw" do
    expect(items.pluck(:icon) - AdminHelper::ICONS.keys).to be_empty
    expect(items.pluck(:icon)).to all(be_present)
  end

  it "gives every item a unique id" do
    expect(items.pluck(:id)).to eq(items.pluck(:id).uniq)
  end

  describe ".item_for" do
    it "returns an item the user may see" do
      expect(described_class.item_for(build(:user, access_level: :super_admin), :jobs)).to include(title: "Background Jobs")
    end

    it "returns nil for an item above the user's access level" do
      expect(described_class.item_for(build(:user, :admin), :jobs)).to be_nil
    end
  end
end
