# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::HssMatcher do
  subject(:matcher) { described_class.new({ [ "PHIL", 4501 ] => [ [ "PHIL", 4500 ] ] }) }

  let(:course) { Struct.new(:subject_code, :course_number) { def key = [ subject_code, course_number ] } }
  let(:ethics) { { "name" => "Ethics", "subject_codes" => [], "courses" => %w[PHIL4501] } }
  let(:humanities) { { "name" => "Humanities", "subject_codes" => %w[PHIL HIST], "courses" => [] } }
  let(:open_category) { { "name" => "Writing intensive", "subject_codes" => [], "courses" => [] } }

  it "gives the hint of a category with spaced course codes, and nil for one with no matcher" do
    expect(described_class.hint(ethics)).to eq(subject_codes: [], courses: [ "PHIL 4501" ])
    expect(described_class.hint(open_category)).to be_nil
    expect(described_class.checkable?(open_category)).to be(false)
  end

  it "matches a course by subject, by course, and by a course code alias" do
    expect(matcher.in_category?(ethics, course.new("PHIL", 4501))).to be(true)
    expect(matcher.in_category?(ethics, course.new("PHIL", 4500))).to be(true)
    expect(matcher.in_category?(ethics, course.new("PHIL", 1000))).to be(false)
    expect(matcher.in_category?(humanities, course.new("HIST", 1000))).to be(true)
  end

  it "counts an English course as Humanities only when it is the third English course" do
    english = course.new("ENGL", 2200)

    expect(matcher.in_category?(humanities, english)).to be(false)
    expect(matcher.in_category?(humanities, english, english_humanities: english)).to be(true)
  end

  it "gives the first category in order that a course meets, or nil" do
    expect(matcher.category_of([ humanities, ethics ], course.new("PHIL", 4501))).to eq("Humanities")
    expect(matcher.category_of([ ethics, humanities ], course.new("PHIL", 4501))).to eq("Ethics")
    expect(matcher.category_of([ ethics ], course.new("WDGT", 1000))).to be_nil
  end

  it "knows the elective lists of the HSS slots" do
    expect(described_class.slot_list?("HSS Electives")).to be(true)
    expect(described_class.slot_list?("Humanities Electives")).to be(true)
    expect(described_class.slot_list?("HSS Elective (PSYC4552)")).to be(true)
    expect(described_class.slot_list?("English Sequence")).to be(false)
    expect(described_class.slot_list?(nil)).to be(false)
  end
end
