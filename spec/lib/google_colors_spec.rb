# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleColors do
  describe ".witcc_to_color_id" do
    context "with valid WITCC colors" do
      it "converts WITCC_TOMATO to EVENT_TOMATO color ID" do
        expect(described_class.witcc_to_color_id("#d50000")).to eq(11)
      end

      it "converts WITCC_FLAMINGO to EVENT_FLAMINGO color ID" do
        expect(described_class.witcc_to_color_id("#e67c73")).to eq(4)
      end

      it "converts WITCC_TANGERINE to EVENT_TANGERINE color ID" do
        expect(described_class.witcc_to_color_id("#f4511e")).to eq(6)
      end

      it "converts WITCC_BANANA to EVENT_BANANA color ID" do
        expect(described_class.witcc_to_color_id("#f6bf26")).to eq(5)
      end

      it "converts WITCC_SAGE to EVENT_SAGE color ID" do
        expect(described_class.witcc_to_color_id("#33b679")).to eq(2)
      end

      it "converts WITCC_BASIL to EVENT_BASIL color ID" do
        expect(described_class.witcc_to_color_id("#0b8043")).to eq(10)
      end

      it "converts WITCC_PEACOCK to EVENT_PEACOCK color ID" do
        expect(described_class.witcc_to_color_id("#039be5")).to eq(7)
      end

      it "converts WITCC_BLUEBERRY to EVENT_BLUEBERRY color ID" do
        expect(described_class.witcc_to_color_id("#3f51b5")).to eq(9)
      end

      it "converts WITCC_LAVENDER to EVENT_LAVENDER color ID" do
        expect(described_class.witcc_to_color_id("#7986cb")).to eq(1)
      end

      it "converts WITCC_GRAPE to EVENT_GRAPE color ID" do
        expect(described_class.witcc_to_color_id("#8e24aa")).to eq(3)
      end

      it "converts WITCC_GRAPHITE to EVENT_GRAPHITE color ID" do
        expect(described_class.witcc_to_color_id("#616161")).to eq(8)
      end

      it "handles uppercase hex values" do
        expect(described_class.witcc_to_color_id("#D50000")).to eq(11)
      end

      it "handles mixed case hex values" do
        expect(described_class.witcc_to_color_id("#d50000")).to eq(11)
      end
    end

    context "with invalid inputs" do
      it "returns nil for blank input" do
        expect(described_class.witcc_to_color_id("")).to be_nil
      end

      it "returns nil for nil input" do
        expect(described_class.witcc_to_color_id(nil)).to be_nil
      end

      it "returns nil for non-WITCC color" do
        expect(described_class.witcc_to_color_id("#ffffff")).to be_nil
      end

      it "returns nil for invalid color format" do
        expect(described_class.witcc_to_color_id("not-a-color")).to be_nil
      end
    end
  end

  describe ".to_witcc_hex" do
    context "with Google color IDs" do
      it "converts color ID 11 to WITCC_TOMATO" do
        expect(described_class.to_witcc_hex(11)).to eq("#d50000")
      end

      it "converts color ID 4 to WITCC_FLAMINGO" do
        expect(described_class.to_witcc_hex(4)).to eq("#e67c73")
      end

      it "converts color ID 6 to WITCC_TANGERINE" do
        expect(described_class.to_witcc_hex(6)).to eq("#f4511e")
      end

      it "converts color ID 5 to WITCC_BANANA" do
        expect(described_class.to_witcc_hex(5)).to eq("#f6bf26")
      end

      it "converts color ID 2 to WITCC_SAGE" do
        expect(described_class.to_witcc_hex(2)).to eq("#33b679")
      end

      it "converts color ID 10 to WITCC_BASIL" do
        expect(described_class.to_witcc_hex(10)).to eq("#0b8043")
      end

      it "converts color ID 7 to WITCC_PEACOCK" do
        expect(described_class.to_witcc_hex(7)).to eq("#039be5")
      end

      it "converts color ID 9 to WITCC_BLUEBERRY" do
        expect(described_class.to_witcc_hex(9)).to eq("#3f51b5")
      end

      it "converts color ID 1 to WITCC_LAVENDER" do
        expect(described_class.to_witcc_hex(1)).to eq("#7986cb")
      end

      it "converts color ID 3 to WITCC_GRAPE" do
        expect(described_class.to_witcc_hex(3)).to eq("#8e24aa")
      end

      it "converts color ID 8 to WITCC_GRAPHITE" do
        expect(described_class.to_witcc_hex(8)).to eq("#616161")
      end
    end

    context "with Google event hex colors" do
      it "converts EVENT_TOMATO hex to WITCC_TOMATO" do
        expect(described_class.to_witcc_hex("#dc2127")).to eq("#d50000")
      end

      it "converts EVENT_BANANA hex to WITCC_BANANA" do
        expect(described_class.to_witcc_hex("#fbd75b")).to eq("#f6bf26")
      end

      it "handles uppercase hex values" do
        expect(described_class.to_witcc_hex("#DC2127")).to eq("#d50000")
      end
    end

    context "with invalid inputs" do
      it "returns nil for blank input" do
        expect(described_class.to_witcc_hex("")).to be_nil
      end

      it "returns nil for nil input" do
        expect(described_class.to_witcc_hex(nil)).to be_nil
      end

      it "returns nil for unmapped color ID" do
        expect(described_class.to_witcc_hex(99)).to be_nil
      end

      it "returns nil for invalid input type" do
        expect(described_class.to_witcc_hex("not-a-color")).to be_nil
      end
    end
  end
end
