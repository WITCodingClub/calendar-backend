# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SeatRefreshJob do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 10, 28)) { example.run } }

  let!(:running)  { create(:term, uid: 202710, season: :fall, year: 2026, start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)) }
  let!(:upcoming) { create(:term, uid: 202720, season: :spring, year: 2027, start_date: Date.new(2027, 1, 12), end_date: Date.new(2027, 4, 20)) }

  before do
    create(:course, term: running)
    create(:course, term: upcoming)
    allow(Catalog::SeatRefresh).to receive(:call).and_return(0)
  end

  it "refreshes the term students register for, not the term in session" do
    described_class.perform_now

    expect(Catalog::SeatRefresh).to have_received(:call).with(upcoming).once
    expect(Catalog::SeatRefresh).not_to have_received(:call).with(running)
  end

  it "keeps a term in the window until add/drop ends" do
    travel_to(Date.new(2027, 1, 19))
    expect(described_class.terms).to include(upcoming)

    travel_to(Date.new(2027, 1, 20))
    expect(described_class.terms).not_to include(upcoming)
  end

  it "leaves out a future term with no sections yet" do
    create(:term, uid: 202730, season: :summer, year: 2027, start_date: Date.new(2027, 5, 4), end_date: Date.new(2027, 8, 10))

    expect(described_class.terms).to contain_exactly(upcoming)
  end

  it "stops before the next term when Banner starts to cool down" do
    summer = create(:term, uid: 202730, season: :summer, year: 2027, start_date: Date.new(2027, 5, 4), end_date: Date.new(2027, 8, 10))
    create(:course, term: summer)
    remaining = [ nil, 120 ]
    allow(Catalog::BannerThrottle).to receive(:cooldown_remaining) { remaining.shift }

    described_class.perform_now

    expect(Catalog::SeatRefresh).to have_received(:call).once
  end

  it "skips the run while Banner cools down" do
    allow(Catalog::BannerThrottle).to receive(:cooldown_remaining).and_return(120)

    described_class.perform_now

    expect(Catalog::SeatRefresh).not_to have_received(:call)
  end
end
