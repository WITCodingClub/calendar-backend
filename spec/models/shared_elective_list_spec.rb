# frozen_string_literal: true

require "rails_helper"

RSpec.describe SharedElectiveList do
  it "gives the kind of a list by its name" do
    expect(described_class.kind_of("HSS Electives")).to eq(:hss)
    expect(described_class.kind_of("HSS Elective (PSYC4552)")).to eq(:directed_hss)
    expect(described_class.kind_of("Co-op")).to eq(:co_op)
    expect(described_class.kind_of("Computer Science Electives")).to be_nil
  end

  it "knows the HSS lists" do
    expect(described_class.hss?("Humanities Electives")).to be(true)
    expect(described_class.hss?("English Sequence")).to be(false)
    expect(described_class.hss?(nil)).to be(false)
  end

  it "names a directed HSS elective after its course" do
    list = described_class.directed([ "PSYC", 4552 ], "HSS 03 Elective (PSYC4552)")

    expect(list).to have_attributes(kind: :directed_hss, name: "HSS Elective (PSYC4552)", courses: [ [ "PSYC", 4552 ] ])
    expect(described_class.kind_of(list.name)).to eq(:directed_hss)
  end
end
