# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::TermCode do
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
  end

  it "converts a code back to its label" do
    expect(%w[202610 202620 202630].map { |code| described_class.label(code.to_i) })
      .to eq([ "Fall 2025", "Spring 2026", "Summer 2026" ])
  end

  it "puts fall, spring, and summer of one academic year in one catalog year" do
    expect([ 202610, 202620, 202630 ].map { |code| described_class.catalog_year(code) }.uniq).to eq([ "2025-2026" ])
    expect(described_class.catalog_year(202710)).to eq("2026-2027")
  end
end
