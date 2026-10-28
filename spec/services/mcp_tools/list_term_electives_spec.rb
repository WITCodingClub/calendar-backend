# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::ListTermElectives do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  def text(result) = result.content.first[:text]

  before do
    list = create(:term_elective_list, term: term, school: "SCDS")
    create(:term_elective_course, term_elective_list: list, subject_code: "COMP", course_number: 2000, heading: "NET Elective")
    hss = create(:term_elective_list, term: term, school: "HSS")
    create(:term_elective_course, term_elective_list: hss, subject_code: "ECON", course_number: 4102, heading: "Social Science")
  end

  it "lists the elective lists of a term, with the advisory" do
    result = call(term_uid: term.uid)

    expect(result.structured_content[:term]).to eq(uid: term.uid, name: term.name)
    expect(result.structured_content[:lists].pluck(:school)).to eq(%w[HSS SCDS])
    expect(result.structured_content[:advisory][:message]).to include("academic advisor")
  end

  it "uses the current term when no term is given" do
    allow(Term).to receive(:current).and_return(term)

    expect(call.structured_content[:lists].size).to eq(2)
  end

  it "takes a school, a course, and heading words" do
    expect(call(term_uid: term.uid, school: "hss").structured_content[:lists].size).to eq(1)
    expect(call(term_uid: term.uid, course: "COMP 2000").structured_content[:lists].first[:courses].pluck(:code)).to eq([ "COMP 2000" ])
    expect(call(term_uid: term.uid, q: "social").structured_content[:lists].pluck(:school)).to eq(%w[HSS])
  end

  it "returns tool errors for an unknown term or a bad filter" do
    expect(text(call(term_uid: 1))).to include("No term with uid 1")
    expect(text(call(term_uid: term.uid, course: "widgets"))).to include("course must be a course code")
  end
end
