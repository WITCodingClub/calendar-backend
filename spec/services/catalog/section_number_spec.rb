# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SectionNumber do
  it "drops leading zeros" do
    expect(described_class.normalize("01")).to eq("1")
    expect(described_class.normalize(7)).to eq("7")
  end

  it "keeps one zero for a section of only zeros" do
    expect(described_class.normalize("00")).to eq("0")
  end

  it "gives nil for a blank value" do
    expect(described_class.normalize("")).to be_nil
    expect(described_class.normalize(nil)).to be_nil
  end
end
