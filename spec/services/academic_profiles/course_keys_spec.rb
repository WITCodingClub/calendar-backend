# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::CourseKeys do
  subject(:keys) { described_class.new({ [ "COMP", 128 ] => [ [ "COMP", 1000 ] ], [ "COMP", 1000 ] => [ [ "COMP", 128 ] ] }) }

  it "matches a key with its old and new codes, both ways" do
    expect(keys.equivalents([ "COMP", 128 ])).to eq([ [ "COMP", 128 ], [ "COMP", 1000 ] ])
    expect(keys.same?([ "COMP", 1000 ], [ "COMP", 128 ])).to be(true)
    expect(keys.same?([ "COMP", 1000 ], [ "COMP", 2000 ])).to be(false)
    expect(keys.expand([ [ "COMP", 128 ], [ "COMP", 1000 ] ])).to eq([ [ "COMP", 128 ], [ "COMP", 1000 ] ])
  end

  it "gives the old and new codes of a code" do
    expect(keys.equivalent_codes("COMP 128")).to eq([ "COMP 128", "COMP 1000" ])
    expect(keys.equivalent_codes("Free Elective")).to eq([ "Free Elective" ])
  end

  it "reads only the checked aliases, once for each request" do
    create(:course_code_alias, :reviewed, from_subject_code: "COMP", from_course_number: 128, to_subject_code: "COMP", to_course_number: 1000)
    create(:course_code_alias, from_subject_code: "MATH", from_course_number: 175, to_subject_code: "MATH", to_course_number: 1750)

    current = described_class.current
    expect(current.equivalents([ "COMP", 1000 ])).to eq([ [ "COMP", 1000 ], [ "COMP", 128 ] ])
    expect(current.equivalents([ "MATH", 1750 ])).to eq([ [ "MATH", 1750 ] ])
    expect(described_class.current).to be(current)
  end
end
