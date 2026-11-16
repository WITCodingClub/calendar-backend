# frozen_string_literal: true

require "rails_helper"

RSpec.describe Course::ScheduleType do
  it "names the lab types" do
    expect(described_class::TYPES.keys.select { |key| described_class.lab?(key) })
      .to contain_exactly(:laboratory, :online_sync_lab, :rotating_lab)
  end

  it "names the online types" do
    expect(described_class::TYPES.keys.select { |key| described_class.online?(key) })
      .to contain_exactly(:online, :online_blended, :online_sync_lab, :online_sync_lecture)
  end

  it "answers false for a blank or unknown key" do
    expect([ nil, "", "seminar" ].map { |key| described_class.lab?(key) || described_class.online?(key) }).to all(be(false))
  end
end
