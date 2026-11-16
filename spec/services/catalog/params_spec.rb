# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::Params do
  describe ".boolean" do
    it "reads every value but a false one as true" do
      expect([ "true", "1", "yes", true ].map { |value| described_class.boolean(value) }).to all(be(true))
      expect([ "false", "0", "", nil, false ].map { |value| described_class.boolean(value) }).to all(be(false))
    end
  end

  describe ".strict_boolean" do
    it "reads true, false, 1, and 0" do
      expect(described_class.strict_boolean("TRUE", :open_only)).to be(true)
      expect(described_class.strict_boolean(0, :open_only)).to be(false)
      expect(described_class.strict_boolean(true, :open_only)).to be(true)
    end

    it "is nil for a blank value" do
      expect(described_class.strict_boolean("", :open_only)).to be_nil
      expect(described_class.strict_boolean(nil, :open_only)).to be_nil
    end

    it "refuses any other value" do
      expect { described_class.strict_boolean("yes", :open_only) }
        .to raise_error(Catalog::FilterError, 'Invalid open_only "yes"; use true or false')
    end
  end

  describe ".day" do
    it "reads a day name in any case" do
      expect(described_class.day(" Friday ")).to eq("friday")
    end

    it "refuses an unknown day" do
      expect { described_class.day("funday") }.to raise_error(Catalog::FilterError, /Unknown day/)
    end
  end

  describe ".time" do
    it "converts HH:MM to the HHMM integer the columns store" do
      expect(described_class.time("9:05")).to eq(905)
      expect(described_class.time("13:45")).to eq(1345)
    end

    it "passes through the HHMM form" do
      expect(described_class.time("1345")).to eq(1345)
      expect(described_class.time(905)).to eq(905)
    end

    it "returns nil for a blank value" do
      expect(described_class.time(nil)).to be_nil
      expect(described_class.time("")).to be_nil
    end

    it "rejects impossible times and names the value in the message" do
      expect { described_class.time("25:00") }.to raise_error(Catalog::FilterError)
      expect { described_class.time("10:75") }.to raise_error(Catalog::FilterError)
      expect { described_class.time("noon", "earliest time") }
        .to raise_error(Catalog::FilterError, 'Invalid earliest time "noon"; use HH:MM or HHMM')
    end
  end
end
