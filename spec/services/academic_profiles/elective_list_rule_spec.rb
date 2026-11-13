# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::ElectiveListRule do
  def rule(group, aliases = {}) = described_class.new(group, aliases)

  it "takes a course on the list, or an old or new code of one" do
    group = create(:elective_group)
    create(:elective_group_course, elective_group: group, subject_code: "MATH", course_number: 3500)

    list = rule(group, { [ "MATH", 3500 ] => [ [ "MATH", 350 ] ] })

    expect(list.accepts?([ "MATH", 3500 ])).to be(true)
    expect(list.accepts?([ "MATH", 350 ])).to be(true)
    expect(list.accepts?([ "MATH", 3600 ])).to be(false)
    expect(list.accepts_subject?("MATH")).to be(false)
  end

  it "takes any course of a subject of a list of subjects" do
    list = rule(create(:elective_group, :subjects))

    expect(list.accepts?([ "HIST", 1000 ])).to be(true)
    expect(list.accepts?([ "MATH", 1000 ])).to be(false)
    expect(list.accepts_subject?("PSYC")).to be(true)
  end

  it "takes any course for degree credit on a list of any course, but no co-op and no course below 1000" do
    list = rule(create(:elective_group, :any_course))

    expect(list.accepts?([ "MATH", 2100 ])).to be(true)
    expect(list.accepts?([ "ENGL", 700 ])).to be(false)
    expect(list.accepts?([ "COOP", 3500 ])).to be(false)
    expect(list.accepts_subject?("COOP")).to be(false)
    expect(list.any_course?).to be(true)
  end
end
