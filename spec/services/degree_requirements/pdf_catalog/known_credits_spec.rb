# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::KnownCredits do
  it "takes the credits of the nearest HTML catalog year, else the Banner credit hours" do
    near = create(:catalog_year, start_year: 2019)
    far = create(:catalog_year, start_year: 2022)
    # A PDF year holds credits that an earlier import read or guessed.
    own = create(:catalog_year, start_year: 2015)
    create(:catalog_year_course, catalog_year: far, subject_code: "MGMT", course_number: 2500, min_credits: 3, max_credits: 3)
    create(:catalog_year_course, catalog_year: near, subject_code: "MGMT", course_number: 2500, min_credits: 4, max_credits: 4)
    # A PDF year and a credit range are not used.
    create(:catalog_year_course, catalog_year: own, subject_code: "ELEC", course_number: 3150, min_credits: 2, max_credits: 2)
    create(:catalog_year_course, catalog_year: near, subject_code: "ARCH", course_number: 1000, min_credits: 3, max_credits: 4)
    create(:catalog_course, subject_code: "ELEC", course_number: 3150, credit_hours: 4)
    create(:catalog_course, subject_code: "MGMT", course_number: 2500, credit_hours: 2)

    expect(described_class.call(2016)).to eq({ [ "MGMT", 2500 ] => 4, [ "ELEC", 3150 ] => 4 })
  end
  it "takes the credits of a grid year plan only for a course that no other source has" do
    grid = create(:catalog_year, start_year: 2015)
    html = create(:catalog_year, start_year: 2019)
    plan = create(:program_plan, requirement_set: create(:requirement_set, catalog_year: grid))
    create(:program_plan_item, program_plan: plan, subject_code: "FMGT", course_number: 3000, min_credits: 4, max_credits: 4)
    create(:program_plan_item, program_plan: plan, subject_code: "MGMT", course_number: 2500, min_credits: 4, max_credits: 4)
    create(:program_plan_item, program_plan: plan, subject_code: "ENGR", course_number: 1100, min_credits: 3, max_credits: 3)
    # Two plans of the year print different credits for it.
    create(:program_plan_item, program_plan: plan, subject_code: "FMGT", course_number: 3200, min_credits: 3, max_credits: 3)
    create(:program_plan_item, program_plan: plan, subject_code: "FMGT", course_number: 3200, min_credits: 4, max_credits: 4)
    create(:catalog_course, subject_code: "MGMT", course_number: 2500, credit_hours: 3)
    create(:catalog_year_course, catalog_year: html, subject_code: "ENGR", course_number: 1100, min_credits: 2, max_credits: 2)

    expect(described_class.call(2016)).to eq({ [ "FMGT", 3000 ] => 4, [ "MGMT", 2500 ] => 3, [ "ENGR", 1100 ] => 2 })
  end
end
