# frozen_string_literal: true

# == Schema Information
#
# Table name: buildings
#
#  id                          :bigint           not null, primary key
#  abbreviation                :string           not null
#  formal_name                 :string
#  name                        :string           not null
#  twenty_five_live_checked_at :datetime
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  twenty_five_live_id         :integer
#
# Indexes
#
#  index_buildings_on_abbreviation         (abbreviation) UNIQUE
#  index_buildings_on_name                 (name) UNIQUE
#  index_buildings_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
require "rails_helper"

RSpec.describe Building, type: :model do
  fixtures :buildings

  describe ".physical" do
    it "leaves out the TBD and ONLINE placeholders" do
      Building.create!(abbreviation: "TBD", name: "To Be Determined")
      Building.create!(abbreviation: "ONLINE", name: "Online Section")

      expect(Building.physical.pluck(:abbreviation)).to contain_exactly("WT", "COMP")
    end
  end

  describe "#twenty_five_live_status" do
    let(:building) { buildings(:WT) }

    it "is :match when the name equals the 25Live formal name" do
      building.formal_name = "Wentworth Hall"

      expect(building.twenty_five_live_status).to eq(:match)
    end

    it "is :mismatch when the name differs from the 25Live formal name" do
      building.formal_name = "Wentworth"

      expect(building.twenty_five_live_status(sync_in_progress: true)).to eq(:mismatch)
    end

    it "is :syncing with no formal name while a sync runs" do
      building.twenty_five_live_checked_at = 1.day.ago

      expect(building.twenty_five_live_status(sync_in_progress: true)).to eq(:syncing)
    end

    it "is :never_synced when no sync has checked the building" do
      expect(building.twenty_five_live_status).to eq(:never_synced)
    end

    it "is :stale when the last check is older than a missed weekly sync" do
      building.twenty_five_live_checked_at = 9.days.ago

      expect(building.twenty_five_live_status).to eq(:stale)
    end

    it "is :not_in_25live when a recent sync did not find the building" do
      building.twenty_five_live_checked_at = 1.day.ago

      expect(building.twenty_five_live_status).to eq(:not_in_25live)
    end
  end
end
