# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::FinalExamQuery do
  let(:term) { create(:term) }
  let(:comp) { create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000, title: "Data Structures") }
  let(:math) { create(:course, term: term, subject: "MATH", course_number: 1800, title: "Calculus I") }
  let!(:comp_exam) { create(:final_exam, term: term, course: comp, crn: comp.crn, exam_date: Date.new(2026, 12, 16)) }
  let!(:math_exam) { create(:final_exam, term: term, course: math, crn: math.crn, exam_date: Date.new(2026, 12, 15)) }

  def call(**args) = described_class.new.call(term: term, **args).to_a

  it "lists the term's exams by date" do
    create(:final_exam, term: create(:term))

    expect(call).to eq([ math_exam, comp_exam ])
  end

  it "matches a course code in either subject format" do
    expect(call(q: "comp-2000")).to eq([ comp_exam ])
    expect(call(q: "MATH 1800")).to eq([ math_exam ])
  end

  it "matches title words and a CRN" do
    expect(call(q: "data")).to eq([ comp_exam ])
    expect(call(q: math.crn.to_s)).to eq([ math_exam ])
  end

  it "keeps only the given courses" do
    expect(call(course_ids: [ comp.id ])).to eq([ comp_exam ])
    expect(call(course_ids: [])).to eq([])
  end
end
