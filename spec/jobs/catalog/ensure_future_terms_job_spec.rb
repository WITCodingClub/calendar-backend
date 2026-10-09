# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::EnsureFutureTermsJob do
  include ActiveSupport::Testing::TimeHelpers

  def terms_created
    Term.all.map { |t| [ t.year, t.season ] }
  end

  context "in the fall" do
    around { |example| travel_to(Date.new(2026, 10, 9)) { example.run } }

    it "creates the current term and the next six, in order" do
      described_class.perform_now

      expect(terms_created).to match_array(
        [ [ 2026, "fall" ], [ 2027, "spring" ], [ 2027, "summer" ], [ 2027, "fall" ],
          [ 2028, "spring" ], [ 2028, "summer" ], [ 2028, "fall" ] ]
      )
    end

    it "sets the uid from the season and year" do
      described_class.perform_now

      expect(Term.find_by(year: 2026, season: :fall).uid).to eq(202710)
      expect(Term.find_by(year: 2027, season: :spring).uid).to eq(202720)
      expect(Term.find_by(year: 2027, season: :summer).uid).to eq(202730)
    end

    it "honors terms_ahead" do
      described_class.perform_now(terms_ahead: 1)

      expect(terms_created).to match_array([ [ 2026, "fall" ], [ 2027, "spring" ] ])
    end

    it "keeps existing terms and does not duplicate them" do
      existing = create(:term, year: 2027, season: :spring, uid: 202720, catalog_imported: true)

      expect { described_class.perform_now }.to change(Term, :count).by(6)

      expect(Term.where(year: 2027, season: :spring).count).to eq(1)
      expect(existing.reload.catalog_imported).to be(true)
    end

    it "does nothing when every term exists" do
      described_class.perform_now

      expect { described_class.perform_now }.not_to change(Term, :count)
    end
  end

  it "starts at summer from June to July" do
    travel_to(Date.new(2026, 6, 1)) do
      described_class.perform_now(terms_ahead: 0)
    end

    expect(terms_created).to eq([ [ 2026, "summer" ] ])
  end

  it "starts at spring before June" do
    travel_to(Date.new(2026, 5, 31)) do
      described_class.perform_now(terms_ahead: 0)
    end

    expect(terms_created).to eq([ [ 2026, "spring" ] ])
  end

  it "starts at fall from August" do
    travel_to(Date.new(2026, 8, 1)) do
      described_class.perform_now(terms_ahead: 0)
    end

    expect(terms_created).to eq([ [ 2026, "fall" ] ])
  end
end
