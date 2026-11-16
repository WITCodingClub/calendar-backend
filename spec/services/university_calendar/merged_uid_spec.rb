# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::MergedUid do
  it "keeps the uid of a single event" do
    expect(described_class.for([ "one@example.test" ])).to eq("one@example.test")
  end

  it "names the first uid and the count of a merged run" do
    expect(described_class.for(%w[one@example.test two@example.test])).to eq("merged:one@example.test+2")
  end

  it "reads the first uid back" do
    expect(described_class.root("merged:a+b@example.test+3")).to eq("a+b@example.test")
    expect(described_class.root("one@example.test")).to be_nil
  end
end
