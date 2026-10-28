# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::TermElectiveQuery do
  subject(:query) { described_class.new }

  let(:term) { create(:term) }
  let!(:scds) { create(:term_elective_list, term: term, school: "SCDS", title: "Computing Electives") }
  let!(:hss) { create(:term_elective_list, term: term, school: "HSS", title: "HSS Electives") }

  before do
    create(:term_elective_course, term_elective_list: scds, subject_code: "COMP", course_number: 2000, heading: "Computer Science Elective")
    create(:term_elective_course, term_elective_list: scds, subject_code: "MATH", course_number: 4050, heading: "Data Science Elective")
    create(:term_elective_course, term_elective_list: hss, subject_code: "ECON", course_number: 4102, heading: "Social Science")
    create(:term_elective_list)
  end

  def summary(matches) = matches.map { |match| [ match.list.school, match.courses.map(&:code) ] }

  it "gives every list of the term by school, with all its courses" do
    expect(summary(query.call(term: term))).to eq([ [ "HSS", [ "ECON 4102" ] ], [ "SCDS", [ "COMP 2000", "MATH 4050" ] ] ])
  end

  it "keeps a list with no courses when there is no filter" do
    empty = create(:term_elective_list, term: term, school: "SOM")

    expect(query.call(term: term).map(&:list)).to include(empty)
  end

  it "filters by school, in any case" do
    expect(summary(query.call(term: term, school: [ "scds" ]))).to eq([ [ "SCDS", [ "COMP 2000", "MATH 4050" ] ] ])
  end

  it "keeps only the matching course, and leaves out the lists without it" do
    expect(summary(query.call(term: term, course: "math 4050"))).to eq([ [ "SCDS", [ "MATH 4050" ] ] ])
  end

  it "keeps the courses whose heading has every word" do
    expect(summary(query.call(term: term, q: "science data"))).to eq([ [ "SCDS", [ "MATH 4050" ] ] ])
  end

  it "raises a filter error for an unknown school or a bad course code" do
    expect { query.call(term: term, school: "XYZ") }.to raise_error(Catalog::FilterError, /school must be one of/)
    expect { query.call(term: term, course: "widgets") }.to raise_error(Catalog::FilterError, /course must be a course code/)
  end
end
