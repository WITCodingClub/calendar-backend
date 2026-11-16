# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseRequisites do
  it "gives each course it names its code, title, and whether WIT Calendar knows it" do
    known = create(:catalog_course, subject_code: "MATH", course_number: 1750, title: "Calculus I")
    course = create(:catalog_course,
                    prerequisites: { "type" => "or", "operands" => [
                      { "type" => "course", "subject_code" => "MATH", "course_number" => 1750 },
                      { "type" => "test", "name" => "WIT Math Assessment" }
                    ] },
                    corequisites: [ { "subject_code" => "COMP", "course_number" => 9999 } ])
    requisites = described_class.new(course)

    expect(requisites.prerequisites["operands"].first).to include("code" => "MATH 1750", "title" => known.title, "linked" => true)
    expect(requisites.prerequisites["operands"].last).to eq("type" => "test", "name" => "WIT Math Assessment")
    expect(requisites.corequisites.first).to include("code" => "COMP 9999", "title" => nil, "linked" => false)
  end
end
