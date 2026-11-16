# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::NextTermRequest do
  def request(term: nil, assume: nil)
    described_class.new(term: term, assume: assume, assume_plans: false, include_candidates: true)
  end

  it "refuses a term that is not a Banner code or a label" do
    expect { request(term: "Winter 2027") }
      .to raise_error(described_class::InvalidTermError, /Banner term code or a label/)
  end

  it "refuses an assume value that is not course codes" do
    expect { request(assume: "not a code") }.to raise_error(AcademicProfiles::PlanningError, /course codes/)
  end

  it "passes the parsed term and assumed courses to NextTermCourses" do
    user = build(:user)
    courses = instance_double(AcademicProfiles::NextTermCourses, call: { programs: [] })
    allow(AcademicProfiles::NextTermCourses).to receive(:new).and_return(courses)

    expect(request(term: "Spring 2027", assume: "COMP3350, math 2300").call(user)).to eq(programs: [])
    expect(AcademicProfiles::NextTermCourses).to have_received(:new)
      .with(user, term_uid: 202720, assume: [ [ "COMP", 3350 ], [ "MATH", 2300 ] ], assume_plans: false, include_candidates: true)
  end

  it "uses the default term for a blank term" do
    allow(AcademicProfiles::NextTermCourses).to receive(:new).and_return(instance_double(AcademicProfiles::NextTermCourses, call: {}))

    request(term: "").call(build(:user))

    expect(AcademicProfiles::NextTermCourses).to have_received(:new).with(anything, hash_including(term_uid: nil))
  end
end
