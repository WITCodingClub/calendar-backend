# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::FindSchedules do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def call(user: self.user, scopes: nil, **arguments)
    context = mcp_context(user)
    context = context.merge(scopes: scopes) if scopes
    described_class.call(server_context: context, **arguments)
  end

  before do
    create(:catalog_course, subject_code: "COMP", course_number: 3350)
    lecture = create(:course, term: term, crn: 20410, subject: "Computer Science (COMP)", course_number: 3350)
    create(:course_meeting_time, course: lecture, day_of_week: :monday, begin_time: 1000, end_time: 1115)
    late = create(:course, term: term, crn: 20412, subject: "Computer Science (COMP)", course_number: 3350, section_number: "02")
    create(:course_meeting_time, course: late, day_of_week: :friday, begin_time: 1600, end_time: 1715)
  end

  it "builds the same answer as the API" do
    arguments = { term_uid: term.uid, courses: [ { codes: [ "COMP 3350" ] } ], preferences: { day_off: [ "friday" ] } }

    result = call(**arguments)

    expect(result.error?).to be(false)
    expect(result.structured_content.except(:advisory)).to eq(Catalog::ScheduleOptions::Finder.new(arguments).call)
    expect(result.structured_content[:schedules].sole[:crns]).to eq(%w[20410])
  end

  it "uses the current term when no term is given" do
    allow(Term).to receive(:current).and_return(term)

    expect(call(courses: [ { codes: [ "COMP 3350" ] } ]).structured_content[:count]).to eq(2)
  end

  it "gives the relax list when no schedule fits" do
    result = call(term_uid: term.uid, courses: [ { codes: [ "COMP 3350" ] } ], preferences: { latest: "11:00" })

    expect(result.structured_content).to include(count: 0, relax: [ { preference: "latest", label: "Allow classes after 11 AM", count: 2 } ])
  end

  it "answers a bad argument with a tool error" do
    result = call(term_uid: term.uid, courses: [ { codes: [ "COMP 3350" ] } ], preferences: { weekends: true })

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("Unknown preference(s): weekends")
  end

  it "needs the catalog scope" do
    expect(call(scopes: [], term_uid: term.uid, courses: [ { codes: [ "COMP 3350" ] } ]).error?).to be(true)
  end

  it "is read-only and has no flag, like its endpoint" do
    expect(described_class.annotations.read_only_hint).to be(true)
    expect(described_class.required_flag).to be_nil
    expect(described_class.required_scope).to eq("catalog")
  end
end
