# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleColors do
  describe ".normalize" do
    it "keeps a custom hex color, in lowercase" do
      expect(described_class.normalize(" #1A2B3C ")).to eq("#1a2b3c")
    end

    it "turns a legacy color id into the hex of its palette color" do
      expect(described_class.normalize(11)).to eq(described_class::TOMATO)
      expect(described_class.normalize("7")).to eq(described_class::PEACOCK)
    end

    it "rejects values that are not colors" do
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize(12)).to be_nil
      expect(described_class.normalize("0")).to be_nil
      expect(described_class.normalize("red")).to be_nil
      expect(described_class.normalize("#12345")).to be_nil
      expect(described_class.normalize("#1a2b3c; color: red")).to be_nil
    end
  end

  describe ".normalize_attribute" do
    it "turns a blank value into nil" do
      expect(described_class.normalize_attribute("")).to be_nil
    end

    it "keeps a value that is not a color, so that validation rejects it" do
      expect(described_class.normalize_attribute("red")).to eq("red")
    end
  end

  describe ".nearest_color_id" do
    it "gives the id of a palette color" do
      expect(described_class.nearest_color_id(described_class::BASIL)).to eq(10)
    end

    it "gives the id of the nearest palette color for a custom color" do
      expect(described_class.nearest_color_id("#ff0000")).to eq(11)
      expect(described_class.nearest_color_id("#000080")).to eq(9)
    end
  end
end
