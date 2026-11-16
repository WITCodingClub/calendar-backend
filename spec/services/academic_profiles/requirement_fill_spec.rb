# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::RequirementFill do
  let(:set) { create(:requirement_set) }
  let(:plan) { create(:program_plan, requirement_set: set) }
  let(:taken) { Struct.new(:subject_code, :course_number, :status, :credits) { include CourseCode::Named } }
  let(:keys) { AcademicProfiles::CourseKeys.new({}) }

  def fill(pool)
    details = AcademicProfiles::CourseDetails.new([], keys)
    described_class.new(pool, course_keys: keys, credits: AcademicProfiles::CourseCredits.new(details),
                              hss_matcher: AcademicProfiles::HssMatcher.new(keys))
  end

  it "gives a required course row its course before an elective slot can take it" do
    list = create(:elective_group, requirement_set: set, subject_codes: [ "WDGT" ], min_courses: nil)
    slot = create(:program_plan_item, :placeholder, program_plan: plan, elective_group: list)
    row = create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: 1000)
    course = taken.new("WDGT", 1000, "done", 4)

    result = fill([ course ]).plan(set, plan.reload)

    expect(result.courses).to eq(row.id => course, slot.id => nil)
    expect(result.counted).to eq([ course ])
  end

  it "counts the courses of a list up to its minimum" do
    group = create(:elective_group, requirement_set: set, min_courses: 1)
    create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 1000)
    create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 2000)
    first = taken.new("WDGT", 1000, "done", 4)

    lists, counted = fill([ first, taken.new("WDGT", 2000, "done", 4) ]).lists(set.reload)

    expect(lists.map { |list| [ list.courses, list.needed ] }).to eq([ [ [ first ], 1 ] ])
    expect(counted).to eq([ first ])
  end
end
