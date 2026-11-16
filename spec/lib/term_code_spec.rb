# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermCode do
  describe ".parse" do
    it "converts a label to the Banner code" do
      expect(described_class.parse("Fall 2025")).to eq(202610)
      expect(described_class.parse("Spring 2026")).to eq(202620)
      expect(described_class.parse(" summer  2026 ")).to eq(202630)
    end

    it "accepts a Banner code as a string or a number" do
      expect(described_class.parse("202610")).to eq(202610)
      expect(described_class.parse(202620)).to eq(202620)
    end

    it "returns nil for anything else" do
      expect(described_class.parse("Winter 2025")).to be_nil
      expect(described_class.parse("202640")).to be_nil
      expect(described_class.parse("Fall")).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end

    it "returns nil for a year out of range" do
      expect(described_class.parse("Fall 0000")).to be_nil
      expect(described_class.parse("000010")).to be_nil
      expect(described_class.parse("Spring #{Time.zone.today.year + 10}")).to be_nil
    end
  end

  it "converts a code back to its label" do
    expect(%w[202610 202620 202630].map { |code| described_class.label(code.to_i) })
      .to eq([ "Fall 2025", "Spring 2026", "Summer 2026" ])
  end

  it "puts fall, spring, and summer of one academic year in one catalog year" do
    expect([ 202610, 202620, 202630 ].map { |code| described_class.catalog_year(code) }.uniq).to eq([ "2025-2026" ])
    expect(described_class.catalog_year(202710)).to eq("2026-2027")
  end

  it "builds the code of a season of a calendar year" do
    expect(described_class.for(2026, :fall)).to eq(202710)
    expect(described_class.for(2026, "spring")).to eq(202620)
    expect(described_class.for(2026, :summer)).to eq(202630)
    expect(described_class.for(2026, :winter)).to be_nil
  end

  it "splits a code into the calendar year and the season" do
    expect(described_class.year_and_season(202710)).to eq(year: 2026, season: :fall)
    expect(described_class.year_and_season("202630")).to eq(year: 2026, season: :summer)
    expect(described_class.year_and_season(202640)).to be_nil
  end

  it "steps to the next term, and to the next fall or spring term" do
    expect([ 202610, 202620, 202630 ].map { |code| described_class.next_term(code) }).to eq([ 202620, 202630, 202710 ])
    expect([ 202610, 202620, 202630 ].map { |code| described_class.next_regular_term(code) }).to eq([ 202620, 202710, 202710 ])
  end

  it "lists the terms of a catalog year" do
    expect(described_class.catalog_year_codes(2025)).to contain_exactly(202610, 202620, 202630)
    expect(described_class.catalog_start_year(202630)).to eq(2025)
  end

  describe ".plan_term and .plan_year" do
    it "puts year 1 in the academic year of a fall or spring start" do
      expect(described_class.plan_term(202610, 3, "spring")).to eq(202820)
      expect(described_class.plan_term(202620, 1, "fall")).to eq(202610)
      expect(described_class.plan_year(202620, 202610)).to eq(1)
    end

    it "puts year 1 in the academic year after a summer start" do
      expect(described_class.plan_term(202630, 1, "fall")).to eq(202710)
      expect(described_class.plan_year(202630, 202730)).to eq(1)
    end

    it "gives nil without a start term or for a term before year 1" do
      expect(described_class.plan_term(nil, 1, "fall")).to be_nil
      expect(described_class.plan_term(202610, 1, "winter")).to be_nil
      expect(described_class.plan_year(202610, 202520)).to be_nil
    end
  end
end
